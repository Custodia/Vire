defmodule VireWeb.UploadJSON do
  def file(%{file: file}), do: %{id: file.id, status: file.status}

  def show(%{file: file, activity: activity}) do
    %{
      id: file.id,
      status: file.status,
      processor_version: file.processor_version,
      error: file.error,
      activity_id: activity && activity.id
    }
  end
end
