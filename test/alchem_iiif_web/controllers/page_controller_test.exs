defmodule AlchemIiifWeb.PageControllerTest do
  use AlchemIiifWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Enter the Digital Gallery"
  end

  test "browser responses include a Content-Security-Policy header", %{conn: conn} do
    conn = get(conn, ~p"/")
    [csp] = get_resp_header(conn, "content-security-policy")

    assert csp =~ "default-src 'self'"
    assert csp =~ "object-src 'none'"
    assert csp =~ "frame-ancestors 'self'"
  end
end
