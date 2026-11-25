.pragma library
.import "values.js" as V
.import "lexer.js" as Lexer
.import "parser.js" as Parser
.import "builtins.js" as B
// SPDX-License-Identifier: MIT
// The OWL compiler: syntax tree to a program the runtime runs.
//
// It resolves every name, checks node and property names, arities and the
// language level, folds constant expressions, and lists every command, URL
// and file the widget can reach (`commands`, the list the approval sheet
// shows). Expressions become closures `f(env)`; a constant one carries
// `f.isConst` and `f.value`.
//
// The program:
//   { name, meta, level, levelUsed, size, minSize, page, order, padding,
//     background, globals, root, screen, screenTitle, onTap, triggers,
//     commands, requires, needsLinux, animated, terminal, nodeCount }
// `globals` are the widget's slots: { type: "source" | "state" | "let" |
// "sampled" | "asset", name, ... }. `root` and `screen` are node templates:
//   { t: "el", kind, props, handlers, anims, children }
//   { t: "draw", op, args, named, children }      (inside a Canvas)
//   { t: "lets", values, children }  { t: "if", cond, then, otherwise }
//   { t: "for", list, key, body }    { t: "use", component, args, wrapper, body }

var CompileError = Lexer.CompileError

// The level this runtime implements. Terminal (level 2) is not served yet:
// it is refused with its own message (plan §2.4).
var LEVEL = 7
var MAX_TILE_NODES = 500
var MAX_SCREEN_NODES = 1000
var MAX_ASSET_BYTES = 2 * 1024 * 1024
var UNSUPPORTED = { Terminal: "Terminal isn't supported on this phone yet" }

var CONSTANTS = { pi: Math.PI, transparent: new V.Color(null, 0, 1) }

// Actions a handler may run: [fewest, most] values.
var ACTIONS = {
  terminal: [1, 2], app: [1, 1], run: [1, 1], url: [1, 1], launcher: [1, 1], refresh: [0, 1],
  media: [1, 1], androidApp: [1, 1], copy: [1, 1], notify: [1, 2], volume: [1, 1],
  notification: [2, 2], screen: [0, 0], close: [0, 0], torch: [1, 1], share: [1, 1], haptic: [0, 0]
}
var ACTION_WORDS = {
  media: ["toggle", "play", "pause", "next", "previous", "open"],
  volume: ["up", "down", "mute", "unmute", "toggle"],
  torch: ["on", "off", "toggle"],
  notification: ["open", "dismiss"]
}

// Nodes: their own properties, and what their body holds.
var NODES = {
  Column: { props: ["gap", "align", "justify", "scroll"], holds: "nodes" },
  Row: { props: ["gap", "align", "justify", "wrap"], holds: "nodes" },
  Flow: { props: ["gap", "align", "justify"], holds: "nodes" },
  Box: { props: ["align"], holds: "nodes" },
  Grid: { props: ["columns", "gap"], holds: "nodes" },
  Text: { props: ["text", "style", "color", "fontSize", "bold", "italic", "font", "align", "maxLines"], holds: "" },
  Image: { props: ["src", "fit", "tint"], holds: "" },
  Button: { props: ["text", "color"], holds: "" },
  Progress: { props: ["value", "max", "color", "track"], holds: "" },
  Ring: { props: ["value", "max", "color", "track", "thickness", "start", "sweep"], holds: "" },
  Sparkline: { props: ["values", "min", "max", "color", "area", "thickness"], holds: "" },
  Canvas: { props: [], holds: "draw" },
  Shader: { props: ["code", "uniforms", "fallback"], holds: "" },
  Spacer: { props: [], holds: "" },
  Terminal: { props: ["command", "fontSize"], holds: "" },
  Slider: { props: ["value", "min", "max", "step", "color", "track", "live"], holds: "" },
  Input: { props: ["text", "placeholder", "color", "fontSize", "clear", "focus"], holds: "" }
}
var NODE_NAMES = Object.keys(NODES)
var COMMON = ["width", "height", "size", "fill", "weight", "padding", "background", "border", "borderColor",
  "radius", "opacity", "rotation", "scale", "offset", "clip", "visible"]
var ANIMATABLE = ["opacity", "rotation", "scale", "value", "color", "background"]
// Properties whose value can be a bare word: `align: center`, `style: muted`.
var WORDS = {
  style: ["huge", "title", "body", "small", "muted", "label"],
  align: ["start", "center", "end", "top", "bottom", "topStart", "topEnd", "bottomStart", "bottomEnd"],
  justify: ["start", "center", "end", "spaceBetween", "spaceAround", "spaceEvenly"],
  fit: ["contain", "cover", "fill"],
  font: ["mono", "sans", "serif", "icon"],
  fill: ["width", "height"],
  cap: ["round", "butt", "square"]
}
var ALL_WORDS = []
Object.keys(WORDS).forEach(function(k) { ALL_WORDS = ALL_WORDS.concat(WORDS[k]) })

// Drawing calls: [fewest, most] positional values, and whether they wrap a block.
var DRAWING = {
  rect: [4, 4, false], circle: [3, 3, false], arc: [5, 5, false], line: [4, 4, false], path: [1, 1, false],
  text: [3, 3, false], image: [5, 5, false], sprite: [4, 4, false],
  translate: [2, 2, true], rotate: [1, 3, true], scale: [1, 4, true], clip: [4, 4, true], layer: [1, 1, true]
}
var DRAWING_OPTIONS = ["fill", "stroke", "width", "cap", "radius", "closed", "size", "color", "align", "bold", "palette"]

// The level that introduced each feature (the guide's `owl:` table).
var LEVEL_OF = { Terminal: 2, sprite: 3 }
;["Slider", "Input", "file", "android.notifications", "android.volume", "volume", "notification",
  "every", "at", "when", "on"].forEach(function(k) { LEVEL_OF[k] = 4 })
;["screen", "close", "screenWidth", "screenHeight", "optional", "linux", "android.system"]
  .forEach(function(k) { LEVEL_OF[k] = 5 })
;["sh", "corners", "Input.focus"].forEach(function(k) { LEVEL_OF[k] = 6 })
;["android.alarm", "android.modes", "torch", "share", "haptic"].forEach(function(k) { LEVEL_OF[k] = 7 })

var PACKAGE_NAME = { pacman: /^[a-z0-9@_+][a-z0-9@._+-]*$/ }
var HANDLER_ARGS = { onTap: ["x", "y"], onDrag: ["dx", "dy", "x", "y"], onChange: ["value"], onSubmit: ["value"] }
var HANDLER_NODES = { onChange: ["Slider", "Input"], onSubmit: ["Input"] }
var ANDROID_SOURCES = ["battery", "device", "media", "notifications", "volume", "system", "alarm", "modes"]
var TILE_NAMES = ["cols", "rows", "tileWidth", "tileHeight", "screenWidth", "screenHeight", "corners"]
var WIDGET_PROPS = ["size", "minSize", "page", "order", "padding", "background"]

// ---------------------------------------------------------------- closures

function constant(v) {
  var f = function() { return v }
  f.isConst = true
  f.value = v
  return f
}
function evaluate(f, env) { return f.isConst ? f.value : f(env) }

// An environment at run time: slots of one scope and the scope around it.
// `ctx` is the instance's bridge (read, write, theme, time, tile, act,
// runInto, report, spend).
function Env(ctx, up, slots) {
  this.ctx = ctx
  this.up = up
  this.slots = slots
}
function Pending(f) { this.f = f }
Env.prototype.get = function(depth, i) {
  var e = this
  for (var d = 0; d < depth; d++) e = e.up
  var v = e.slots[i]
  if (v instanceof Pending) {
    v = evaluate(v.f, e)
    e.slots[i] = v
  }
  return v === undefined ? null : v
}
Env.prototype.inner = function(slots) { return new Env(this.ctx, this, slots) }
Env.prototype.withLets = function(fs) {
  return new Env(this.ctx, this, fs.map(function(f) { return new Pending(f) }))
}

// What constant folding runs against: no state, no theme, no time.
var FOLDING = {
  spend: function() {},
  read: function() { throw new Error("not constant") },
  write: function() { throw new Error("not constant") },
  theme: function() { return null },
  time: function() { return 0 },
  tile: function() { return null },
  act: function() { throw new Error("not constant") }
}
var FOLD_ENV = new Env(FOLDING, null, [])

// ---------------------------------------------------------------- scopes

function Scope(up, names, visible) {
  this.up = up
  this.names = names
  this.visible = visible === undefined ? names.length : visible
}

function messageOf(e) {
  return e && e.message !== undefined ? e.message : String(e)
}

// ---------------------------------------------------------------- the compiler

function Compiler(ast) {
  this.ast = ast
  this.top = new Scope(null, [])
  this.globals = []
  this.slotOf = {}
  this.states = {}
  this.components = {}
  this.commands = []
  this.httpPrefixes = []
  this.actions = []           // the actions handlers can run, by name, first use first
  this.needsLinux = false
  this.animated = false
  this.terminal = false
  this.nodes = 0
  this.nodeLimit = MAX_TILE_NODES
  this.screenCall = null
  this.newest = null          // [level, feature, at]: the newest feature used
  this.inScreen = null
}

Compiler.prototype = {
  fail: function(message, at) { throw new CompileError(message, at) },

  uses: function(feature, at) {
    var level = LEVEL_OF[feature]
    if (level !== undefined && level > (this.newest ? this.newest[0] : 1)) this.newest = [level, feature, at]
  },

  program: function() {
    var self = this
    var body = this.ast.body
    var meta = []
    body.decls.forEach(function(d) { if (d.decl === "meta") meta = meta.concat(d.fields) })
    var levelField = meta.filter(function(f) { return f.name === "owl" })[0] || null
    var level = 1
    if (levelField) {
      var n = V.toNumber(this.constantOf(levelField.value, "meta values"))
      if (n === null) this.fail("owl: takes a number, like owl: 1", levelField.at)
      level = V.toInt32(n)
    }
    if (level > LEVEL)
      this.fail("this widget needs owl " + level + "; this phone supports up to " + LEVEL + ", so update Omamobile", levelField.at)
    if (body.anims.length) this.fail("animate belongs inside a node", body.anims[0].at)
    body.handlers.forEach(function(h) {
      if (h.name !== "onTap") self.fail("a widget only takes onTap at the top level", h.at)
    })

    // Sources, states and assets first, so a let may read one declared below it.
    body.decls.forEach(function(d) {
      var named = d.decl !== "meta" && d.decl !== "trigger" && d.decl !== "requires"
      if (named && Object.prototype.hasOwnProperty.call(self.slotOf, d.name)) self.fail("'" + d.name + "' is already declared", d.at)
      if (d.decl === "source" || d.decl === "state" || d.decl === "asset") self.reserve(d.name, d.at)
      if (d.decl === "state") self.states[d.name] = true
    })
    body.decls.forEach(function(d) {
      switch (d.decl) {
      case "source": self.globals[self.slotOf[d.name]] = self.source(d); break
      case "state":
        self.globals[self.slotOf[d.name]] = { type: "state", name: d.name, init: self.expr(d.init, self.top), persist: d.persist }
        break
      case "asset": self.globals[self.slotOf[d.name]] = self.asset(d); break
      case "let": {
        var g = self.letDecl(d)
        self.reserve(d.name, d.at)
        self.globals[self.slotOf[d.name]] = g
        break
      }
      case "component":
        if (Object.prototype.hasOwnProperty.call(self.components, d.name) || NODES.hasOwnProperty(d.name))
          self.fail("'" + d.name + "' is already a node", d.at)
        self.components[d.name] = self.component(d)
        break
      }
    })
    var triggers = body.decls.filter(function(d) { return d.decl === "trigger" }).map(function(d) { return self.trigger(d) })

    var props = {}
    body.props.forEach(function(p) {
      props[p.name] = p
      if (WIDGET_PROPS.indexOf(p.name) < 0)
        self.fail("unknown widget property '" + p.name + "' (" + WIDGET_PROPS.join(", ") + ")", p.at)
    })
    var metaValues = {}
    meta.forEach(function(f) { metaValues[f.name] = self.constantOf(f.value, "meta values") })
    var requiresFields = []
    body.decls.forEach(function(d) { if (d.decl === "requires") requiresFields = requiresFields.concat(d.fields) })
    var requires = this.requires(requiresFields)

    var screens = body.items.filter(function(it) { return it.item === "node" && it.type === "screen" })
    if (screens.length > 1) this.fail("a widget has one screen { }", screens[1].at)
    this.inScreen = false
    var root = this.items(body.items.filter(function(it) { return screens.indexOf(it) < 0 }), this.top, "nodes")
    if (!root.length) this.fail("a widget needs at least one node, like Text { text: \"hi\" }", 0)
    var tileNodes = this.nodes
    var screen = screens.length ? this.screen(screens[0]) : null
    var onTap = body.handlers.length ? this.handler(body.handlers[0], this.top) : null
    if (screen === null && this.screenCall !== null)
      this.fail("screen() and close() need a screen { } block in the widget", this.screenCall)
    if (this.newest && level < this.newest[0])
      this.fail(this.newest[1] + " needs owl " + this.newest[0] + ": add meta { owl: " + this.newest[0] + " }", this.newest[2])

    var padding = 12
    if (props.padding) {
      var pv = V.toNumber(this.constantOf(props.padding.value, "padding"))
      if (pv !== null) padding = pv
    }
    return {
      name: this.ast.name === null ? "widget" : this.ast.name,
      meta: metaValues,
      level: level,
      levelUsed: this.newest ? this.newest[0] : 1,
      size: props.size ? this.cells(props.size) : null,
      minSize: props.minSize ? this.cells(props.minSize) : [1, 1],
      page: props.page ? Math.max(this.wholeNumber(props.page), 1) : 1,
      order: props.order ? this.wholeNumber(props.order) : 0,
      padding: padding,
      background: props.background ? this.expr(props.background.value, this.top) : null,
      globals: this.globals,
      root: root,
      screen: screen ? screen.nodes : null,
      screenTitle: screen ? screen.title : null,
      onTap: onTap,
      triggers: triggers,
      commands: this.commands,
      httpPrefixes: this.httpPrefixes,
      actions: this.actions,
      requires: requires,
      needsLinux: this.needsLinux || Object.keys(requires).length > 0,
      animated: this.animated,
      terminal: this.terminal,
      nodeCount: tileNodes
    }
  },

  screen: function(n) {
    var self = this
    this.uses("screen", n.at)
    var body = n.body
    body.props.forEach(function(p) {
      if (p.name !== "title") self.fail("a screen only takes title (its nodes go inside it)", p.at)
    })
    if (body.handlers.length) this.fail("handlers go on the nodes inside a screen", body.handlers[0].at)
    if (body.anims.length) this.fail("animate belongs inside a node", body.anims[0].at)
    this.nodes = 0
    this.nodeLimit = MAX_SCREEN_NODES
    this.inScreen = true
    var nodes = this.items(body.items, this.top, "nodes")
    if (!nodes.length) this.fail("a screen needs at least one node", n.at)
    return { nodes: nodes, title: body.props.length ? this.expr(body.props[0].value, this.top) : null }
  },

  reserve: function(name, at) {
    if (B.THEME_NAMES.indexOf(name) >= 0 || CONSTANTS.hasOwnProperty(name) || name === "time")
      this.fail("'" + name + "' is a built-in name", at)
    this.slotOf[name] = this.globals.length
    this.globals.push(null)
  },

  constantOf: function(e, what) {
    var f = this.expr(e, this.top)
    if (!f.isConst) this.fail(what + " must be constant", e.at)
    return f.value
  },

  wholeNumber: function(p) {
    var n = V.toNumber(this.constantOf(p.value, p.name))
    if (n === null) this.fail(p.name + " must be a number", p.at)
    return V.toInt32(n)
  },

  cells: function(p) {
    var v = this.constantOf(p.value, p.name)
    var ok = Array.isArray(v) && v.length === 2 && V.toNumber(v[0]) !== null && V.toNumber(v[1]) !== null
    if (!ok) this.fail(p.name + " is columns x rows, like 3x2", p.at)
    return [Math.max(V.toInt32(V.toNumber(v[0])), 1), Math.max(V.toInt32(V.toNumber(v[1])), 1)]
  },

  // The command text as listed, or what it is built from.
  listed: function(f, what) {
    return f.isConst && typeof f.value === "string" ? f.value : what
  },

  source: function(d) {
    var e = d.expr
    var callName = e.e === "call" ? e.name : null
    if (d.status && callName !== "cmd" && callName !== "http")
      this.fail("status only works on cmd(...) and http(...)", d.at)
    if (d.optional) {
      if (["cmd", "stream", "file"].indexOf(callName) < 0)
        this.fail("optional only works on cmd(...), stream(...) and file(...), which need Linux", d.at)
      this.uses("optional", d.at)
    }
    var prefix = d.optional ? "if Linux is installed: " : ""
    var every = d.every ? V.toNumber(this.constantOf(d.every, "every")) : null
    var timeout = 10
    if (d.timeout) {
      var t = V.toNumber(this.constantOf(d.timeout, "timeout"))
      if (t !== null) timeout = V.toInt32(t)
    }
    var g = { type: "source", name: d.name, kind: null, arg: null, every: 0, json: d.json,
              timeout: Math.max(1, Math.min(300, timeout)), status: d.status, headers: null, optional: d.optional }
    if (callName === "http") {
      if (e.args.length < 1 || e.args.length > 2 || e.named.length)
        this.fail("http(\"https://...\") takes a URL and optionally a map of headers", e.at)
      var url = this.expr(e.args[0], this.top)
      if (url.isConst && typeof url.value === "string" && !/^https?:\/\//.test(url.value))
        this.fail("http takes an http:// or https:// URL", e.args[0].at)
      this.commands.push("http GET " + this.listed(url, "(a URL built from widget values)"))
      // The literal start of a built URL, so its host can still be known.
      this.httpPrefixes.push(url.isConst ? String(url.value) : e.args[0].e === "text" && e.args[0].parts[0].e === "lit" ? String(e.args[0].parts[0].v) : "")
      g.kind = "http"
      g.arg = url
      g.every = Math.max(every === null ? 60 : every, 5)
      g.headers = e.args.length > 1 ? this.expr(e.args[1], this.top) : null
      return g
    }
    if (callName === "cmd" || callName === "stream") {
      if (e.args.length !== 1 || e.named.length) this.fail(callName + "(\"command\") takes one command", e.at)
      var command = this.expr(e.args[0], this.top)
      this.commands.push(prefix + this.listed(command, callName + "(…) built from widget values"))
      if (!d.optional) this.needsLinux = true
      g.kind = callName
      g.arg = command
      g.every = Math.max(every === null ? 60 : every, 1)
      return g
    }
    if (callName === "file") {
      if (e.args.length !== 1 || e.named.length) this.fail("file(\"~/path\") takes one path", e.at)
      if (d.every || d.timeout) this.fail("file(...) updates when the file changes; it takes no every or timeout", d.at)
      var path = this.expr(e.args[0], this.top)
      if (path.isConst && typeof path.value === "string" && path.value.charAt(0) !== "/" && path.value.indexOf("~/") !== 0)
        this.fail("file takes a path starting with / or ~/", e.args[0].at)
      this.commands.push(prefix + "read file " + this.listed(path, "(a path built from widget values)"))
      this.uses("file", e.at)
      if (!d.optional) this.needsLinux = true
      g.kind = "file"
      g.arg = path
      g.timeout = 0
      return g
    }
    if (e.e === "name" && e.name === "clock") {
      g.kind = "clock"
      g.every = Math.max(every === null ? 1 : every, 0.1)
      g.timeout = 0
      return g
    }
    if (e.e === "member" && e.obj.e === "name" && e.obj.name === "android") {
      if (ANDROID_SOURCES.indexOf(e.name) < 0)
        this.fail("unknown android source '" + e.name + "' (" + ANDROID_SOURCES.join(", ") + ")", e.at)
      this.uses("android." + e.name, e.at)
      if (e.name === "notifications") this.commands.push("read Android notifications (apps, titles and text)")
      g.kind = "android." + e.name
      g.every = Math.max(every === null ? 60 : every, 1)
      g.timeout = 0
      g.json = false
      return g
    }
    this.fail("a source is cmd(\"...\"), stream(\"...\"), http(\"...\"), file(\"...\"), clock, or android." + ANDROID_SOURCES.join("/"), e.at)
  },

  requires: function(fields) {
    var self = this
    var out = {}
    fields.forEach(function(f) {
      var valid = PACKAGE_NAME[f.name]
      if (!valid) self.fail("unknown package manager '" + f.name + "' (" + Object.keys(PACKAGE_NAME).join(", ") + ")", f.at)
      var v = self.constantOf(f.value, "requires")
      var names
      if (typeof v === "string") names = [v]
      else if (Array.isArray(v)) names = v.map(function(item) {
        if (typeof item !== "string") self.fail("package names are strings, like \"jq\"", f.value.at)
        return item
      })
      else self.fail(f.name + " takes a list of package names, like [\"jq\", \"curl\"]", f.value.at)
      names.forEach(function(n) { if (!valid.test(n)) self.fail("'" + n + "' isn't a valid " + f.name + " package name", f.value.at) })
      var list = out[f.name] || (out[f.name] = [])
      names.forEach(function(n) { if (list.indexOf(n) < 0) list.push(n) })
    })
    return out
  },

  asset: function(d) {
    var b = d.base64
    var digits = b.replace(/=+$/, "")
    if (!/^[A-Za-z0-9+\/]*={0,2}$/.test(b) || digits.length % 4 === 1)
      this.fail("asset '" + d.name + "' isn't valid base64", d.at)
    if (Math.floor(digits.length * 3 / 4) > MAX_ASSET_BYTES) this.fail("asset '" + d.name + "' is over 2 MB", d.at)
    return { type: "asset", name: d.name, base64: b }
  },

  letDecl: function(d) {
    var v = d.value
    if (v.e === "call" && (v.name === "history" || v.name === "prev")) {
      var of = v.args[0]
      if (!of) this.fail(v.name + "(value) needs a value", v.at)
      if (v.name === "history") {
        var keep = 60
        if (v.args[1]) {
          var k = V.toNumber(this.constantOf(v.args[1], "history length"))
          if (k !== null) keep = V.toInt32(k)
        }
        return { type: "sampled", name: d.name, of: this.expr(of, this.top), keep: Math.max(2, Math.min(1000, keep)), prev: false, persist: d.persist }
      }
      if (d.persist) this.fail("only history(...) and state persist; prev(...) refills from the next sample", d.at)
      return { type: "sampled", name: d.name, of: this.expr(of, this.top), keep: 2, prev: true, persist: false }
    }
    if (d.persist) this.fail("a let is recomputed from what it reads; persist a state or a history(...) instead", d.at)
    return { type: "let", name: d.name, value: this.expr(v, this.top) }
  },

  trigger: function(d) {
    this.uses(d.trigger, d.at)
    var when
    if (d.trigger === "every") {
      var s = V.toNumber(this.constantOf(d.expr, "every"))
      if (s === null) this.fail("every takes an interval, like every 10s { ... }", d.expr.at)
      if (s < 1) this.fail("every runs at most once a second", d.expr.at)
      when = constant(s)
    } else {
      when = this.expr(d.expr, this.top)
      if (when.isConst) this.fail(d.trigger + " needs a value that changes, like a state or a source", d.expr.at)
    }
    return {
      kind: d.trigger,
      expr: when,
      action: this.handler({ name: d.trigger, stmts: d.stmts, at: d.at }, this.top, d.trigger === "on" ? ["value", "old"] : []),
      at: d.at
    }
  },

  component: function(d) {
    var self = this
    if (d.body.props.length || d.body.handlers.length)
      this.fail("a component's body holds nodes; put properties on a node inside it", d.at)
    var names = d.params.map(function(p) { return p.name })
    var defaults = d.params.map(function(p) { return p.fallback ? self.expr(p.fallback, self.top) : null })
    return { params: names, defaults: defaults, body: this.items(d.body.items, new Scope(this.top, names), "nodes") }
  },

  // A node body's items. Its lets become one scope around the rest, each let
  // seeing the ones before it.
  items: function(list, scope, mode) {
    var self = this
    var lets = list.filter(function(it) { return it.item === "let" })
    if (!lets.length) return list.map(function(it) { return self.item(it, scope, mode) })
    var frame = new Scope(scope, lets.map(function(l) { return l.name }), 0)
    var values = lets.map(function(l) {
      var f = self.expr(l.value, frame)
      frame.visible++
      return f
    })
    var rest = list.filter(function(it) { return it.item !== "let" }).map(function(it) { return self.item(it, frame, mode) })
    return [{ t: "lets", values: values, children: rest, at: lets[0].at }]
  },

  plainBlock: function(body, where) {
    if (body.props.length) this.fail("properties can't go inside " + where + "; use cond ? a : b on the property instead", body.props[0].at)
    if (body.handlers.length) this.fail("handlers can't go inside " + where, body.handlers[0].at)
    if (body.anims.length) this.fail("animate can't go inside " + where, body.anims[0].at)
    if (body.decls.length) this.fail("declarations belong at the top of the widget", body.decls[0].at)
  },

  item: function(it, scope, mode) {
    switch (it.item) {
    case "if": {
      this.plainBlock(it.then, "if")
      if (it.otherwise) this.plainBlock(it.otherwise, "else")
      var cond = this.expr(it.cond, scope)
      return { t: "if", cond: cond, then: this.items(it.then.items, scope, mode),
               otherwise: it.otherwise ? this.items(it.otherwise.items, scope, mode) : [], at: it.at }
    }
    case "for": {
      this.plainBlock(it.body, "for")
      var list = this.expr(it.list, scope)
      var inner = new Scope(scope, [it.name, it.index === null ? "\u0000index" : it.index])
      return { t: "for", list: list, key: it.key ? this.expr(it.key, inner) : null,
               body: this.items(it.body.items, inner, mode), at: it.at }
    }
    case "draw":
      if (mode !== "draw") this.fail(it.call.name + "(...) draws, so it goes inside a Canvas", it.at)
      return this.drawing(it, scope)
    case "node":
      if (mode === "draw") this.fail("a Canvas holds drawing calls like circle(...), not nodes", it.at)
      return this.element(it, scope)
    }
    throw new Error("unexpected item " + it.item)
  },

  drawing: function(it, scope) {
    var self = this
    var c = it.call
    var shape = DRAWING[c.name]
    if (!shape) this.fail("unknown drawing call '" + c.name + "' (" + Object.keys(DRAWING).join(", ") + ")", c.at)
    if (c.args.length < shape[0] || c.args.length > shape[1])
      this.fail(c.name + " takes " + shape[0] + (shape[1] !== shape[0] ? "-" + shape[1] : "") + " values", c.at)
    if (shape[2] && it.body === null) this.fail(c.name + "(...) wraps drawing calls: " + c.name + "(...) { ... }", c.at)
    if (!shape[2] && it.body !== null) this.fail(c.name + "(...) takes no { } body", c.at)
    c.named.forEach(function(n) {
      if (DRAWING_OPTIONS.indexOf(n.name) < 0) self.fail("unknown option '" + n.name + "' (" + DRAWING_OPTIONS.join(", ") + ")", n.value.at)
    })
    this.uses(c.name, c.at)
    this.nodes++
    var named = {}
    c.named.forEach(function(n) { named[n.name] = self.wordOrExpr(n.name, n.value, scope) })
    var children = null
    if (it.body) {
      this.plainBlock(it.body, c.name)
      children = this.items(it.body.items, scope, "draw")
    }
    return { t: "draw", op: c.name, args: c.args.map(function(a) { return self.expr(a, scope) }), named: named, children: children, at: it.at }
  },

  element: function(n, scope) {
    var self = this
    this.nodes++
    if (this.nodes > this.nodeLimit)
      this.fail("more than " + this.nodeLimit + " nodes; " + (this.nodeLimit === MAX_TILE_NODES ? "widgets" : "screens") + " should stay small", n.at)
    if (n.type === "screen") this.fail("screen { } goes at the top of the widget, next to its nodes", n.at)
    var body = n.body
    if (body.decls.length) this.fail("declarations belong at the top of the widget", body.decls[0].at)
    if (Object.prototype.hasOwnProperty.call(this.components, n.type)) return this.use(n, this.components[n.type], scope)
    var spec = NODES[n.type]
    if (!spec) this.fail("unknown node '" + n.type + "' (" + NODE_NAMES.concat(Object.keys(this.components)).join(", ") + ")", n.at)
    var props = {}
    body.props.forEach(function(p) {
      if (spec.props.indexOf(p.name) < 0 && COMMON.indexOf(p.name) < 0)
        self.fail(n.type + " has no property '" + p.name + "' (" + spec.props.concat(COMMON).join(", ") + ")", p.at)
      if (props.hasOwnProperty(p.name)) self.fail("'" + p.name + "' is set twice", p.at)
      // On a tile it would raise the keyboard whenever its page shows.
      if (p.name === "focus" && self.inScreen === false) self.fail("focus only works in a screen { }", p.at)
      self.uses(n.type + "." + p.name, p.at)
      props[p.name] = self.wordOrExpr(p.name, p.value, scope)
    })
    var handlers = {}
    body.handlers.forEach(function(h) {
      if (!HANDLER_ARGS.hasOwnProperty(h.name))
        self.fail("unknown handler '" + h.name + "' (" + Object.keys(HANDLER_ARGS).join(", ") + ")", h.at)
      var only = HANDLER_NODES[h.name]
      if (only && only.indexOf(n.type) < 0) self.fail(h.name + " only works on " + only.join(" and "), h.at)
      handlers[h.name] = self.handler(h, scope)
    })
    var anims = {}
    body.anims.forEach(function(a) {
      if (ANIMATABLE.indexOf(a.name) < 0) self.fail("'" + a.name + "' can't animate (" + ANIMATABLE.join(", ") + ")", a.at)
      anims[a.name] = self.expr(a.value, scope)
    })
    this.uses(n.type, n.at)
    if (n.type === "Terminal") {
      this.terminal = true
      this.commands.push(!props.command ? "a terminal running the login shell"
        : this.listed(props.command, "Terminal command built from widget values"))
      this.needsLinux = true
    }
    if (n.type === "Shader") this.animated = true
    if (spec.holds === "" && body.items.length) this.fail(n.type + " can't hold other nodes", body.items[0].at)
    var children = spec.holds === "" ? []
      : spec.holds === "nodes" ? this.items(body.items, scope, "nodes")
      : this.items(body.items, new Scope(scope, ["width", "height"]), "draw")
    return { t: "el", kind: n.type, props: props, handlers: handlers, anims: anims, children: children, at: n.at }
  },

  use: function(n, component, scope) {
    var self = this
    var body = n.body
    if (body.items.length) this.fail(n.type + " takes no child nodes", body.items[0].at)
    if (body.handlers.length || body.anims.length) this.fail("put handlers and animate inside the component", n.at)
    var given = {}
    body.props.forEach(function(p) {
      given[p.name] = p
      if (component.params.indexOf(p.name) < 0 && COMMON.indexOf(p.name) < 0)
        self.fail(n.type + " has no parameter '" + p.name + "' (" + component.params.join(", ") + ")", p.at)
    })
    var args = component.params.map(function(name, i) {
      if (given.hasOwnProperty(name)) return self.expr(given[name].value, scope)
      if (component.defaults[i] === null) self.fail(n.type + " needs '" + name + "'", n.at)
      return component.defaults[i]
    })
    var wrapper = {}
    body.props.forEach(function(p) {
      if (component.params.indexOf(p.name) < 0) wrapper[p.name] = self.wordOrExpr(p.name, p.value, scope)
    })
    return { t: "use", component: n.type, args: args, wrapper: wrapper, body: component.body, at: n.at }
  },

  // `align: center`: a bare word the property takes, unless the widget
  // declared something by that name.
  wordOrExpr: function(prop, e, scope) {
    var words = WORDS[prop]
    if (words && e.e === "name" && words.indexOf(e.name) >= 0 && this.lookup(e.name, scope) === null) return constant(e.name)
    return this.expr(e, scope)
  },

  handler: function(h, scope, argNames) {
    var self = this
    var params = argNames || HANDLER_ARGS[h.name] || []
    var inner = new Scope(scope, params)
    var steps = h.stmts.map(function(s) {
      if (s.stmt === "assign") return self.assignment(s, inner)
      var c = s.call
      var arity = ACTIONS[c.name]
      if (!arity) self.fail("'" + c.name + "' isn't an action (" + Object.keys(ACTIONS).join(", ") + ")", c.at)
      if (c.args.length < arity[0] || c.args.length > arity[1])
        self.fail(c.name + " takes " + arity[0] + "-" + arity[1] + " values", c.at)
      var args = c.args.map(function(a) { return self.expr(a, inner) })
      var first = args.length && args[0].isConst && typeof args[0].value === "string" ? args[0].value : null
      var words = ACTION_WORDS[c.name]
      if (words && first !== null && words.indexOf(first) < 0 && !(c.name === "volume" && V.toNumber(first) !== null)) {
        if (c.name === "volume") self.fail("volume takes a level in percent, or " + words.join(", "), c.at)
        if (c.name === "torch") self.fail("torch takes true, false, " + words.join(", "), c.at)
        if (c.name === "notification") self.fail("notification takes " + words.join(", ") + " and a notification's key", c.at)
        self.fail(c.name + " takes " + words.join(", "), c.at)
      }
      self.uses(c.name, c.at)
      if (self.actions.indexOf(c.name) < 0) self.actions.push(c.name)
      if ((c.name === "screen" || c.name === "close") && self.screenCall === null) self.screenCall = c.at
      if (c.name === "run" || c.name === "terminal" || c.name === "app") {
        self.commands.push(first !== null ? first : c.name + "(…) built from widget values")
        if (c.name === "run") self.needsLinux = true
      }
      var action = c.name
      return function(env) { env.ctx.act(action, args.map(function(a) { return evaluate(a, env) })) }
    })
    var name = h.name
    return {
      params: params,
      run: function(env, values) {
        var e = params.length ? env.inner(params.map(function(p, i) { return i < values.length ? values[i] : null })) : env
        try {
          env.ctx.guarded(function() { steps.forEach(function(step) { step(e) }) })
        } catch (x) {
          env.ctx.report(name + ": " + messageOf(x))
        }
      }
    }
  },

  assignment: function(s, scope) {
    var known = Object.prototype.hasOwnProperty.call(this.slotOf, s.name)
    if (!known || !this.states[s.name])
      this.fail(!known ? "unknown state '" + s.name + "'; declare it with: state " + s.name + " = ..."
        : "'" + s.name + "' isn't a state and can't be assigned", s.at)
    var slot = this.slotOf[s.name]
    var call = s.value.e === "call" ? s.value : null
    if (call && call.name === "run") {
      if (call.args.length !== 1 || call.named.length) this.fail("run takes one command", call.at)
      var command = this.expr(call.args[0], scope)
      this.commands.push(this.listed(command, "run(…) built from widget values"))
      this.needsLinux = true
      return function(env) { env.ctx.runInto(V.display(evaluate(command, env)), slot) }
    }
    var value = this.expr(s.value, scope)
    return function(env) { env.ctx.write(slot, evaluate(value, env)) }
  },

  lookup: function(name, scope) {
    var depth = 0
    for (var s = scope; s !== null; s = s.up, depth++) {
      var i = s.names.slice(0, s.visible).lastIndexOf(name)
      if (i >= 0) return { local: true, depth: depth, index: i }
    }
    if (Object.prototype.hasOwnProperty.call(this.slotOf, name)) return { local: false, slot: this.slotOf[name] }
    return null
  },

  // Constant inputs make a constant, unless evaluating it fails (then it is
  // left to fail, or not, at run time).
  fold: function(inputs, f) {
    for (var i = 0; i < inputs.length; i++) if (!inputs[i].isConst) return f
    try {
      return constant(f(FOLD_ENV))
    } catch (e) {
      return f
    }
  },

  expr: function(e, scope) {
    var self = this
    switch (e.e) {
    case "lit": return constant(e.v)
    case "color": return constant(new V.Color(null, V.parseHex(e.hex), 1))
    case "name": return this.name(e, scope)
    case "text": {
      var parts = e.parts.map(function(p) { return self.expr(p, scope) })
      var literal = e.parts.map(function(p) { return p.e === "lit" && typeof p.v === "string" })
      return this.fold(parts, function(env) {
        var out = ""
        for (var i = 0; i < parts.length; i++) {
          var v = evaluate(parts[i], env)
          out += literal[i] ? V.display(v) : V.textOf(v)
        }
        return out
      })
    }
    case "list": {
      var items = e.items.map(function(it) { return self.expr(it, scope) })
      return this.fold(items, function(env) { return items.map(function(it) { return evaluate(it, env) }) })
    }
    case "map": {
      var keys = e.keys
      var vals = e.values.map(function(v) { return self.expr(v, scope) })
      return this.fold(vals, function(env) {
        var m = new Map()
        for (var i = 0; i < keys.length; i++) m.set(keys[i], evaluate(vals[i], env))
        return m
      })
    }
    case "unary": {
      var x = this.expr(e.x, scope)
      if (e.op === "!") return this.fold([x], function(env) { return !V.truthy(evaluate(x, env)) })
      return this.fold([x], function(env) {
        var n = V.toNumber(evaluate(x, env))
        return n === null ? null : -n
      })
    }
    case "binary": return this.binary(e, scope)
    case "cond": {
      var test = this.expr(e.test, scope), yes = this.expr(e.yes, scope), no = this.expr(e.no, scope)
      if (test.isConst) return V.truthy(test.value) ? yes : no
      return function(env) { return V.truthy(evaluate(test, env)) ? evaluate(yes, env) : evaluate(no, env) }
    }
    case "member": {
      var obj = this.expr(e.obj, scope)
      var field = e.name
      return this.fold([obj], function(env) { return B.memberOf(evaluate(obj, env), field) })
    }
    case "index": {
      var target = this.expr(e.obj, scope), key = this.expr(e.key, scope)
      return this.fold([target, key], function(env) { return indexInto(evaluate(target, env), evaluate(key, env)) })
    }
    case "call": return this.call(e, scope)
    case "lambda": {
      var params = e.params
      var bodyF = this.expr(e.body, new Scope(scope, params))
      var n = params.length
      return function(env) {
        return new V.Lambda(n, function(args) {
          env.ctx.spend(1)
          var slots = []
          for (var i = 0; i < n; i++) slots.push(i < args.length ? args[i] : null)
          return evaluate(bodyF, env.inner(slots))
        })
      }
    }
    }
    throw new Error("unknown expression " + e.e)
  },

  binary: function(e, scope) {
    var l = this.expr(e.l, scope), r = this.expr(e.r, scope)
    switch (e.op) {
    case "&&": return this.fold([l, r], function(env) { var v = evaluate(l, env); return V.truthy(v) ? evaluate(r, env) : v })
    case "||": return this.fold([l, r], function(env) { var v = evaluate(l, env); return V.truthy(v) ? v : evaluate(r, env) })
    case "??": return this.fold([l, r], function(env) { var v = evaluate(l, env); return v !== null ? v : evaluate(r, env) })
    }
    var op = OPERATORS[e.op]
    return this.fold([l, r], function(env) { return op(evaluate(l, env), evaluate(r, env)) })
  },

  name: function(e, scope) {
    var ref = this.lookup(e.name, scope)
    if (ref !== null && ref.local) {
      var depth = ref.depth, index = ref.index
      return function(env) { return env.get(depth, index) }
    }
    if (ref !== null) {
      var slot = ref.slot
      return function(env) { return env.ctx.read(slot) }
    }
    if (CONSTANTS.hasOwnProperty(e.name)) return constant(CONSTANTS[e.name])
    if (B.THEME_NAMES.indexOf(e.name) >= 0) return constant(new V.Color(e.name, V.UNRESOLVED, 1))
    if (e.name === "time") {
      this.animated = true
      return function(env) { return env.ctx.time() }
    }
    if (TILE_NAMES.indexOf(e.name) >= 0 || e.name === "linux") {
      this.uses(e.name, e.at)
      var tileName = e.name
      return function(env) { return env.ctx.tile(tileName) }
    }
    if (ALL_WORDS.indexOf(e.name) >= 0) this.fail("'" + e.name + "' isn't a value here", e.at)
    this.fail("unknown name '" + e.name + "'", e.at)
  },

  call: function(e, scope) {
    var self = this
    if (ACTIONS.hasOwnProperty(e.name)) this.fail(e.name + "(...) is an action; use it in a handler like onTap", e.at)
    if (e.name === "history" || e.name === "prev")
      this.fail(e.name + "(...) keeps samples over time, so it only works as: let x = " + e.name + "(...)", e.at)
    if (["cmd", "stream", "http", "file"].indexOf(e.name) >= 0)
      this.fail(e.name + "(...) is a source: source x = " + e.name + "(\"...\")", e.at)
    var def = Object.prototype.hasOwnProperty.call(B.FUNCTIONS, e.name) ? B.FUNCTIONS[e.name] : null
    if (!def) this.fail("unknown function '" + e.name + "'", e.at)
    this.uses(e.name, e.at)
    if (e.named.length) this.fail(e.name + " takes no named arguments", e.named[0].value.at)
    if (e.args.length < def.min || e.args.length > def.max)
      this.fail(e.name + " takes " + (def.min === def.max ? String(def.min) : def.min + "-" + def.max) + " arguments, not " + e.args.length, e.at)
    var args = e.args.map(function(a) { return self.expr(a, scope) })
    var name = e.name
    var f = function(env) {
      env.ctx.spend(1)
      var values = []
      for (var i = 0; i < args.length; i++) values.push(evaluate(args[i], env))
      try {
        return def.run(new B.ArgReader(values, env.ctx))
      } catch (x) {
        if (x instanceof V.RuntimeError) throw x
        throw new V.RuntimeError(name + ": " + messageOf(x))
      }
    }
    if (def.pure && args.every(function(a) { return a.isConst })) {
      try {
        return constant(f(FOLD_ENV))
      } catch (x) {
        this.fail(messageOf(x) || "can't evaluate", e.at)
      }
    }
    return f
  }
}

function indexInto(v, key) {
  if (Array.isArray(v)) {
    var n = V.toNumber(key)
    if (n === null) return null
    var i = V.toInt32(n)
    var item = v[i < 0 ? v.length + i : i]
    return item === undefined ? null : item
  }
  if (v instanceof Map) {
    var f = v.get(V.display(key))
    return f === undefined ? null : f
  }
  if (typeof v === "string") {
    var m = V.toNumber(key)
    if (m === null) return null
    var j = V.toInt32(m)
    var at = j < 0 ? v.length + j : j
    return at < 0 || at >= v.length ? null : v.charAt(at)
  }
  return null
}

function numeric(f) {
  return function(a, b) {
    if (typeof a === "number" && typeof b === "number") return f(a, b)
    var x = V.toNumber(a), y = V.toNumber(b)
    return x === null || y === null ? null : f(x, y)
  }
}
function comparing(test) {
  return function(a, b) {
    if (typeof a === "number" && typeof b === "number") {
      if (a !== a || b !== b) return test(a !== a && b !== b ? 0 : a !== a ? 1 : -1)
      return test(a < b ? -1 : a > b ? 1 : 0)
    }
    if (a === null || b === null) return false
    return test(V.order(a, b))
  }
}

var OPERATORS = {
  "+": function(a, b) {
    if (typeof a === "number" && typeof b === "number") return a + b
    if (Array.isArray(a) && Array.isArray(b)) { var both = a.concat(b); return both.length > 1000 ? both.slice(0, 1000) : both }
    // Text joins as written; anything else beside text reads as it would on screen.
    if (typeof a === "string" || typeof b === "string")
      return (typeof a === "string" ? a : V.textOf(a)) + (typeof b === "string" ? b : V.textOf(b))
    var x = V.toNumber(a), y = V.toNumber(b)
    return x !== null && y !== null ? x + y : null
  },
  "-": numeric(function(x, y) { return x - y }),
  "*": numeric(function(x, y) { return x * y }),
  // Dividing by zero gives 0 rather than infinity (SPEC-NOTES N5).
  "/": numeric(function(x, y) { return y === 0 ? 0 : x / y }),
  "%": numeric(function(x, y) { return y === 0 ? 0 : ((x % y) + y) % y }),
  "==": function(a, b) { return V.equalish(a, b) },
  "!=": function(a, b) { return !V.equalish(a, b) },
  "<": comparing(function(c) { return c < 0 }),
  "<=": comparing(function(c) { return c <= 0 }),
  ">": comparing(function(c) { return c > 0 }),
  ">=": comparing(function(c) { return c >= 0 })
}

function compile(src) {
  return new Compiler(Parser.parse(src)).program()
}

// "3:14: message", the line, and a caret under the column: what the error
// card, .errors/ and an agent read.
function formatError(src, e) {
  if (!(e instanceof CompileError)) return messageOf(e)
  var where = position(src, e.at)
  var lines = src.split("\n")
  var text = where.line - 1 < lines.length ? lines[where.line - 1].replace(/\s+$/, "") : ""
  return where.line + ":" + where.column + ": " + e.message + "\n  " + text + "\n  " + new Array(where.column).join(" ") + "^"
}

function position(src, at) {
  var line = 1, column = 1
  for (var i = 0; i < Math.min(at, src.length); i++) {
    if (src.charAt(i) === "\n") { line++; column = 1 } else column++
  }
  return { line: line, column: column }
}

if (typeof module !== "undefined") {
  module.exports = {
    compile: compile, formatError: formatError, position: position, CompileError: CompileError,
    Env: Env, evaluate: evaluate, constant: constant, LEVEL: LEVEL, UNSUPPORTED: UNSUPPORTED,
    NODES: NODES, COMMON: COMMON, ACTIONS: ACTIONS, MAX_TILE_NODES: MAX_TILE_NODES, MAX_SCREEN_NODES: MAX_SCREEN_NODES,
    messageOf: messageOf
  }
}
