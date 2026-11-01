defmodule VireWeb.DayJSON do
  alias VireWeb.TrainingJSON

  def index(%{dates: dates, days: days, matched: matched, unmatched: unmatched}) do
    %{
      days:
        Enum.map(
          dates,
          &show(%{
            date: &1,
            day: Map.get(days, &1),
            matched: matched,
            unmatched: Map.get(unmatched, &1, [])
          })
        )
    }
  end

  def show(%{date: date, day: day, matched: matched, unmatched: unmatched}) do
    %{
      date: date,
      day: day && TrainingJSON.day(day, matched),
      activities: Enum.map(unmatched, &TrainingJSON.activity_summary/1)
    }
  end
end
