// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/cuevolution"
import topbar from "../vendor/topbar"
import Cropper from "../vendor/cropper.min.js"
import * as echarts from "echarts"

// Exposed globally rather than imported directly in the .PhotoCropper
// colocated hook (lib/cuevolution_web/live/player/registration_live.html.heex)
// — colocated hooks are extracted into their own compiled module, with no
// stable relative import path back to assets/vendor/.
window.Cropper = Cropper

const chartColors = ["#0D0C22", "#E32219", "#D9A02B"]

const EChart = {
  mounted() {
    this.chart = echarts.init(this.el)
    this.resizeObserver = new ResizeObserver(() => this.chart?.resize())
    this.resizeObserver.observe(this.el)
    this.renderChart()
  },
  updated() {
    this.renderChart()
  },
  destroyed() {
    this.resizeObserver?.disconnect()
    this.chart?.dispose()
  },
  renderChart() {
    const data = JSON.parse(this.el.dataset.chartData || "{}")
    const type = this.el.dataset.chartType
    const compact = this.el.clientWidth < 420
    const axisFontSize = compact ? 10 : 12
    const common = {textStyle: {fontFamily: "IBM Plex Mono, monospace", fontSize: axisFontSize}}

    const options = {
      region: {
        ...common,
        grid: {left: compact ? 56 : 72, right: compact ? 8 : 16, top: 12, bottom: 28},
        tooltip: {trigger: "axis", axisPointer: {type: "shadow"}},
        legend: {show: false},
        xAxis: {type: "value", splitLine: {lineStyle: {color: "#F3F3F4"}}, axisLabel: {color: "#9E9EA7", fontSize: axisFontSize}},
        yAxis: {type: "category", data: data.categories || [], axisLabel: {color: "#524B63", fontSize: axisFontSize}, axisLine: {show: false}, axisTick: {show: false}},
        series: (data.series || []).map((series, index) => ({...series, type: "bar", stack: "players", barMaxWidth: 22, itemStyle: {color: chartColors[index], borderRadius: index === 1 ? [0, 4, 4, 0] : [4, 0, 0, 4]}}))
      },
      trend: {
        ...common,
        grid: {left: compact ? 28 : 36, right: compact ? 8 : 14, top: 18, bottom: 34},
        tooltip: {trigger: "axis"},
        xAxis: {type: "category", data: data.labels || [], boundaryGap: false, axisLabel: {color: "#9E9EA7", fontSize: axisFontSize, interval: compact ? 4 : 2}, axisLine: {lineStyle: {color: "#E7E7E9"}}, axisTick: {show: false}},
        yAxis: {type: "value", minInterval: 1, splitLine: {lineStyle: {color: "#F3F3F4"}}, axisLabel: {color: "#9E9EA7", fontSize: axisFontSize}},
        series: [{type: "line", data: data.values || [], smooth: true, symbol: "circle", symbolSize: 7, itemStyle: {color: "#E32219"}, lineStyle: {width: 3, color: "#E32219"}, areaStyle: {color: "rgba(227,34,25,.12)"}}]
      }
    }

    this.chart.setOption(options[type] || {}, true)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, EChart},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
