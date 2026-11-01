defmodule VireWeb.PlanChangeControllerTest do
  use VireWeb.ConnCase, async: true

  import Vire.TrainingFixtures

  alias Vire.Accounts.Scope
  alias Vire.Mcp
  alias Vire.Training

  setup %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    plan = plan_fixture(scope)

    %{conn: sign_in(conn, user), scope: scope, plan: plan}
  end

  test "answers the user's changes newest first, with what they acted on and why", %{
    conn: conn,
    scope: scope,
    plan: plan
  } do
    {:ok, %{id: client_id}} =
      Mcp.register_client(%{name: "Coach", redirect_uris: ["https://coach.example/cb"]})

    mcp = %Scope{user: scope.user, channel: :mcp, mcp_client_id: client_id}

    session =
      session_fixture(mcp,
        structure: %{"title" => "Threshold ride"},
        rationale: "Opens the block"
      )

    {:ok, _} = Training.delete_session(mcp, session.id, "HRV below its band")

    assert %{"changes" => [deleted, created | rest]} =
             conn |> get(~p"/api/plan_changes") |> json_response(200)

    assert %{
             "entity" => "session",
             "action" => "delete",
             "subject" => "Threshold ride",
             "rationale" => "HRV below its band",
             "channel" => "mcp",
             "client" => "Coach"
           } = deleted

    assert %{"action" => "insert", "rationale" => "Opens the block"} = created
    assert is_binary(deleted["at"])

    assert %{"entity" => "season", "subject" => season_name, "client" => nil} = List.last(rest)
    assert season_name == plan.season.name
  end

  test "titles an untitled session after its discipline", %{conn: conn, scope: scope} do
    session_fixture(scope, discipline: :swim, structure: %{})

    assert %{"changes" => [%{"entity" => "session", "subject" => "Swim"} | _]} =
             conn |> get(~p"/api/plan_changes") |> json_response(200)
  end

  test "answers none of another user's changes" do
    other = sign_in(build_conn(), user_fixture())

    assert %{"changes" => []} = other |> get(~p"/api/plan_changes") |> json_response(200)
  end

  test "requires a signed-in user" do
    assert build_conn() |> get(~p"/api/plan_changes") |> json_response(401)
  end
end
