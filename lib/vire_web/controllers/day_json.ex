defmodule VireWeb.DayJSON do
  alias VireWeb.TrainingJSON

  def show(%{date: date, day: day, matched: matched, unmatched: unmatched}) do
    %{
      date: date,
      day: day && TrainingJSON.day(day, matched),
      activities: Enum.map(unmatched, &TrainingJSON.activity_summary/1)
    }
  end
end
