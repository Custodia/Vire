dashboard_built? = File.exists?(Application.app_dir(:vire, "priv/static/index.html"))

ExUnit.start(exclude: if(dashboard_built?, do: [], else: [:dashboard_build]))
Ecto.Adapters.SQL.Sandbox.mode(Vire.Repo, :manual)
