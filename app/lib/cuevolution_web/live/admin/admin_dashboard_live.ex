defmodule CuevolutionWeb.AdminDashboardLive do
  use CuevolutionWeb, :live_view

  alias CuevolutionWeb.AdminComponents

  # Fake data (design-and-functionality pass per project-scope/Quevolution/
  # Cuevolution Admin.dc.html) — swap for real Competitions-context queries
  # once the qualification pipeline / draws / results contexts exist.
  @stat_tiles [
    %{
      label: "Registered players",
      value: "482",
      delta: "+18 this week",
      delta_class: "text-green-600"
    },
    %{label: "Active teams", value: "96", delta: "+3 this week", delta_class: "text-green-600"},
    %{label: "Regions", value: "8", delta: nil, delta_class: "text-ink-500"},
    %{
      label: "Fixtures this week",
      value: "34",
      delta: "12 unplayed",
      delta_class: "text-ink-500"
    },
    %{
      label: "Pending results",
      value: "7",
      delta: "needs attention",
      delta_class: "text-red-600"
    },
    %{label: "Notifications sent", value: "1,204", delta: "24h", delta_class: "text-ink-500"}
  ]

  @attention_items [
    %{icon: "⚠", title: "5 fixtures need results entered", sub: "Regional stage · Nairobi A"},
    %{icon: "✉", title: "3 notification deliveries failed", sub: "SMS · InvalidSenderId"},
    %{
      icon: "◆",
      title: "2 players pending region assignment",
      sub: "Custom \"Other\" location entries"
    }
  ]

  @pipeline_bars [
    %{label: "Regional", count: 320, pct: "100%", color: "#c81e16"},
    %{label: "Zonal", count: 128, pct: "40%", color: "#e32219"},
    %{label: "National", count: 48, pct: "15%", color: "#16a34a"},
    %{label: "Finals", count: 16, pct: "5%", color: "#0d0c22"}
  ]

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Dashboard",
       stat_tiles: @stat_tiles,
       attention_items: @attention_items,
       pipeline_bars: @pipeline_bars
     )}
  end
end
