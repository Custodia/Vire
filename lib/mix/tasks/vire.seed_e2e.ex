defmodule Mix.Tasks.Vire.SeedE2e do
  @shortdoc "Creates the user and the plan the end-to-end suite runs against"

  @moduledoc """
  Prepares the end-to-end database before the server starts. Every run leaves
  the same state, so it is safe to run against a database kept from an earlier
  run.

    * The user e2e@example.com with the password `e2e-password-1234` and an
      invented Garmin key, unless the user exists.
    * The Garmin connection unpaused, so Sync now can queue a sync.
    * A plan through the end of the year after the current one. A user
      without a season gets a season from 2026-01-01 with one phase and one
      block over the same dates. A user with seasons has the latest one, its
      first phase and that phase's first block extended to that end when they
      end sooner.
    * A cycle from 2026-07-13 to 2026-07-19, holding the ride and run fixtures'
      dates, a cycle from today through the following six days, and one from
      tomorrow through the following six days, each unless a cycle already
      holds its first date. Today is the UTC date.
    * A bike session on 2026-07-14, a run on 2026-07-16, and a run and a swim
      both today and tomorrow, each unless its day has a session at its
      position. Tomorrow's pair keeps the suite's view of today intact when a
      run crosses UTC midnight. Nothing is planned on the swim fixture's date,
      2026-01-20.
    * The activities already recorded on those dates matched to the sessions.
  """

  use Mix.Task

  alias Vire.Accounts
  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.Scope
  alias Vire.Repo
  alias Vire.Training
  alias Vire.Training.Period

  @email "e2e@example.com"
  @password "e2e-password-1234"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    scope = Scope.for_user(user())
    today = Date.utc_today()

    resume_garmin(scope)
    block = plan_block(scope, Date.new!(today.year + 1, 12, 31))
    Enum.each(cycles(today), &ensure_cycle(scope, block, &1))
    Enum.each(sessions(today), &ensure_session(scope, &1))
    Enum.each(sessions(today), &Training.match_activities(scope, &1.date))
  end

  defp user do
    case Accounts.get_user_by_email_and_password(@email, @password) do
      nil -> create_user()
      user -> user
    end
  end

  defp create_user do
    user_attrs = %{email: @email, name: "End-to-end Athlete", password: @password}
    connection_attrs = %{provider: :garmin, credential: "invented-garmin-key"}

    case Accounts.create_user_with_provider_connection(user_attrs, connection_attrs) do
      {:ok, user} ->
        Mix.shell().info("Created user #{user.id} #{user.email}")
        user

      {:error, changeset} ->
        Mix.raise("Could not create the e2e user: #{inspect(changeset.errors)}")
    end
  end

  defp resume_garmin(scope) do
    case Accounts.get_provider_connection(scope, :garmin) do
      %ProviderConnection{paused_at: %DateTime{}} = connection ->
        connection |> Ecto.Changeset.change(paused_at: nil) |> Repo.update!()

      _unpaused ->
        :ok
    end
  end

  defp plan_block(scope, last) do
    case Training.list_seasons(scope) do
      [] -> create_plan(scope, last)
      seasons -> extend_plan(scope, List.last(seasons).id, last)
    end
  end

  defp extend_plan(scope, season_id, last) do
    case Training.get_plan(scope, season_id) do
      %{phases: [%{blocks: [block | _]} = phase | _]} = season ->
        extend(scope, &Training.update_season/4, season, last)
        extend(scope, &Training.update_phase/4, phase, last)
        extend(scope, &Training.update_block/4, block, last)
        block

      _season ->
        Mix.raise("The e2e user's latest season has no block")
    end
  end

  defp extend(scope, update, %{id: id, period: %Period{first: first, last: ends}}, last) do
    if Date.before?(ends, last) do
      {:ok, _extended} =
        update.(scope, id, %{period: Period.new(first, last)}, "Keeps the plan ahead of today.")
    end
  end

  defp create_plan(scope, last) do
    period = %{first: ~D[2026-01-01], last: last}

    {:ok, season} =
      Training.create_season(scope, %{
        name: "Autumn 10 km",
        period: period,
        rationale: "Build towards a 10 km road race with a bike and swim base."
      })

    {:ok, phase} =
      Training.create_phase(scope, season.id, %{
        name: "Base",
        period: period,
        rationale: "Aerobic volume before any race-specific work."
      })

    {:ok, block} =
      Training.create_block(scope, phase.id, %{
        focus: "Aerobic endurance",
        period: period,
        rationale: "Mostly easy hours with one quality session a week."
      })

    block
  end

  defp cycles(today) do
    tomorrow = Date.add(today, 1)

    [
      Period.new(~D[2026-07-13], ~D[2026-07-19]),
      Period.new(today, Date.add(today, 6)),
      Period.new(tomorrow, Date.add(tomorrow, 6))
    ]
  end

  defp ensure_cycle(scope, block, %Period{first: first} = period) do
    if is_nil(Training.get_day(scope, first)) do
      {:ok, _cycle} =
        Training.create_cycle(scope, block.id, %{
          kind: :load,
          period: period,
          rationale: "A steady week of easy volume."
        })
    end
  end

  defp ensure_session(scope, %{date: date, position: position} = attrs) do
    day = Training.get_day(scope, date)

    if not Enum.any?(day.sessions, &(&1.position == position)) do
      {:ok, _session} = Training.create_session(scope, attrs)
    end
  end

  defp sessions(today) do
    fixture_sessions() ++ today_sessions(today) ++ today_sessions(Date.add(today, 1))
  end

  defp fixture_sessions do
    [
      %{
        date: ~D[2026-07-14],
        position: 0,
        discipline: :bike,
        planned_seconds: 600,
        rationale: "A short spin to check the position on the new saddle.",
        structure: %{
          "title" => "Saddle check ride",
          "note" => "Seated throughout, easy gears.",
          "steps" => [
            %{"kind" => "warmup", "seconds" => 120, "zone" => 1},
            %{"kind" => "work", "seconds" => 360, "zone" => 2, "target" => "150 W"},
            %{"kind" => "cooldown", "seconds" => 120, "zone" => 1}
          ]
        }
      },
      %{
        date: ~D[2026-07-16],
        position: 0,
        discipline: :run,
        planned_seconds: 600,
        rationale: "Loosens the legs after two days off.",
        structure: %{
          "title" => "Shakeout run",
          "note" => "Conversational pace.",
          "steps" => [
            %{"kind" => "warmup", "seconds" => 120, "zone" => 1},
            %{"kind" => "work", "seconds" => 360, "zone" => 2},
            %{"kind" => "cooldown", "seconds" => 120, "zone" => 1}
          ]
        }
      }
    ]
  end

  defp today_sessions(date) do
    [
      %{
        date: date,
        position: 0,
        discipline: :run,
        planned_seconds: 2460,
        rationale: "Raises the pace that can be held for an hour, ahead of the 10 km.",
        structure: %{
          "title" => "Threshold intervals",
          "note" => "Run every repeat at the same pace.",
          "steps" => [
            %{"kind" => "warmup", "seconds" => 600, "zone" => 1},
            %{
              "repeat" => 3,
              "steps" => [
                %{"kind" => "work", "seconds" => 300, "zone" => 4, "target" => "4:10 /km"},
                %{"kind" => "recovery", "seconds" => 120, "zone" => 1}
              ]
            },
            %{"kind" => "cooldown", "seconds" => 600, "zone" => 1}
          ]
        }
      },
      %{
        date: date,
        position: 1,
        discipline: :swim,
        planned_seconds: 960,
        rationale: "Keeps the stroke long while the running load rises.",
        structure: %{
          "title" => "Technique swim",
          "note" => "Count the strokes on every length.",
          "steps" => [
            %{"kind" => "warmup", "seconds" => 300, "zone" => 1, "note" => "easy freestyle"},
            %{
              "repeat" => 4,
              "steps" => [
                %{"kind" => "work", "seconds" => 90, "zone" => 3, "note" => "100 m freestyle"},
                %{"kind" => "rest", "seconds" => 30}
              ]
            },
            %{"kind" => "cooldown", "seconds" => 180, "zone" => 1}
          ]
        }
      }
    ]
  end
end
