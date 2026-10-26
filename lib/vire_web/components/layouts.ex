defmodule VireWeb.Layouts do
  @moduledoc """
  The document around every server-rendered page, with its stylesheet inline.
  The stylesheet's hash is the only style the content security policy allows.
  """

  use VireWeb, :html

  @style """
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; background: #0f1115; color: #eef0f3;
    font: 16px/1.5 system-ui, sans-serif; display: flex; justify-content: center; }
  main { width: 100%; max-width: 26rem; padding: 2.5rem 1rem; }
  h1 { font-size: 1.5rem; line-height: 1.2; margin: 0 0 1rem; }
  p, ul { margin: 0 0 1rem; color: #9aa3ad; }
  strong { color: #eef0f3; }
  form { display: grid; gap: 1rem; background: #171a20; padding: 1.25rem; border-radius: 12px; }
  label { display: grid; gap: 0.25rem; font-size: 0.875rem; color: #9aa3ad; }
  input { font: inherit; padding: 0.75rem; border-radius: 8px; border: 1px solid #2a2f38;
    background: #0f1115; color: #eef0f3; }
  button { font: inherit; font-weight: 600; padding: 0.75rem; border-radius: 8px; border: 0;
    background: #c6f135; color: #0f1115; cursor: pointer; }
  button.secondary { background: transparent; color: #eef0f3; border: 1px solid #2a2f38; }
  .error { color: #ff8a80; }
  """

  embed_templates "layouts/*"

  def style, do: @style

  @doc "The `style-src` source that admits the inline stylesheet."
  def style_source,
    do: "'sha256-#{Base.encode64(:crypto.hash(:sha256, @style))}'"
end
