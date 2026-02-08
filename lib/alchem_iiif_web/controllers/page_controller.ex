defmodule AlchemIiifWeb.PageController do
  use AlchemIiifWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
