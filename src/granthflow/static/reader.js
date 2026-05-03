/* granthflow reader — epub.js glue
   Renders the book, restores position, persists highlights and reading location. */
(function () {
  "use strict";

  const BOOK = window.BOOK;
  const HL_URL = `/book/${BOOK.id}/highlights`;
  const POST_HL_URL = `/book/${BOOK.id}/highlight`;
  const LOC_URL = `/book/${BOOK.id}/location`;

  const COLOR_HEX = {
    yellow: "#fff3a3",
    green:  "#c2efc2",
    pink:   "#ffc8d6",
    blue:   "#c7defc",
  };

  const book = ePub(BOOK.fileUrl);
  const rendition = book.renderTo("viewer", {
    width: "100%",
    height: "100%",
    spread: "auto",
    allowScriptedContent: false,
  });
  // exposed for tests / debugging — not relied on by app code
  window.book = book;
  window.rendition = rendition;

  const startCfi = BOOK.lastLocation && BOOK.lastLocation.length ? BOOK.lastLocation : undefined;
  rendition.display(startCfi).then(() => { window.__readerReady = true; });

  // ---- snapshot of the visible iframe → cached canvas, refreshed on every relocate
  const viewerFrame = document.querySelector(".viewer-frame");
  let cachedSnap = null;       // HTMLCanvasElement

  async function snapshotCurrent() {
    const iframe = viewerFrame.querySelector("#viewer iframe");
    if (!iframe || !iframe.contentDocument) return null;
    const body = iframe.contentDocument.body;
    if (!body) return null;
    const scrollX = iframe.contentWindow.scrollX || 0;
    const scrollY = iframe.contentWindow.scrollY || 0;
    const dpr = window.devicePixelRatio || 1;
    const w = iframe.offsetWidth, h = iframe.offsetHeight;
    try {
      // html2canvas paints the entire body (paginated columns are wider than viewport);
      // we crop to the visible window after.
      const full = await html2canvas(body, {
        backgroundColor: getComputedStyle(iframe.contentDocument.documentElement).backgroundColor || "#fff",
        logging: false,
        scale: dpr,
      });
      const cropped = document.createElement("canvas");
      cropped.width = w * dpr;
      cropped.height = h * dpr;
      cropped.style.width = "100%";
      cropped.style.height = "100%";
      const ctx = cropped.getContext("2d");
      ctx.drawImage(full, scrollX * dpr, scrollY * dpr, w * dpr, h * dpr, 0, 0, cropped.width, cropped.height);
      return cropped;
    } catch (_) {
      return null;
    }
  }

  function refreshSnapshot() {
    snapshotCurrent().then((c) => { if (c) cachedSnap = c; });
  }

  // ---- WebGL cylindrical page curl
  //
  // Vertex shader bends a tessellated grid around a cylinder of radius u_radius
  // whose axis lies on the curl line. The curl line moves from the anchored corner
  // toward the opposite corner over the animation, in aspect-corrected page space.
  //
  // Three regions per vertex:
  //   flat: u_along ≥ u_curlDist           — untouched
  //   curl: u_curlDist - π·r ≤ u_along < u_curlDist — wrapped around the cylinder
  //   back: u_along < u_curlDist - π·r       — past the curl, hanging off the back
  const PEEL_MS = 700;
  const PEEL_GRID = 60;
  const PEEL_RADIUS = 0.06;            // click-animation default

  // Adaptive curl geometry — the cylinder radius scales so the corner pins to the
  // cursor. Derivation: the BACK region's xy for the corner (along=0) collapses to
  // anchor + r(π−2)·curlDir, so for it to equal anchor + d·curlDir we need r = d/(π−2)
  // and curlDist = d + π·r. Rearranged the same relation gives r = curlDist/(2π−2).
  // MIN clamps r away from zero for tiny curls (avoids vertex-shader Inf when along
  // briefly enters the CURL region with sub-pixel r).
  const PEEL_RADIUS_MIN = 0.04;
  // Cap r for sanity but allow it to exceed page extent — at d≈diagonal, r≈1.07,
  // which is a very loose curl with most of the page in the BACK (flat) region.
  // That matches iBooks: a fully folded page has a gentle, wide bend.
  const PEEL_RADIUS_MAX = 2.0;
  const TWO_PI_MINUS_2 = 2 * Math.PI - 2;
  const PI_MINUS_2 = Math.PI - 2;

  function radiusFromCurlDist(curlDist) {
    return Math.max(PEEL_RADIUS_MIN, Math.min(PEEL_RADIUS_MAX, curlDist / TWO_PI_MINUS_2));
  }

  function easeInOutCubic(t) {
    return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  }

  const VS_SRC = `
    attribute vec2 a_pos;
    varying vec2 v_uv;
    varying float v_phase;
    varying vec3 v_normal;
    uniform float u_aspect;
    uniform vec2 u_corner;
    uniform vec2 u_curlDir;
    uniform float u_curlDist;
    uniform float u_radius;
    #define PI 3.14159265
    void main() {
      vec2 pAcs = vec2(a_pos.x, a_pos.y * u_aspect);
      vec2 cAcs = vec2(u_corner.x, u_corner.y * u_aspect);
      vec2 toP = pAcs - cAcs;
      float along = dot(toP, u_curlDir);
      vec2 perp = toP - along * u_curlDir;
      vec2 axis = cAcs + u_curlDist * u_curlDir + perp;
      vec3 pos3;
      vec3 nrm;
      if (along >= u_curlDist) {
        pos3 = vec3(pAcs, 0.0);
        nrm = vec3(0.0, 0.0, 1.0);
        v_phase = 0.0;
      } else if (along >= u_curlDist - PI * u_radius) {
        float arc = u_curlDist - along;
        float theta = arc / u_radius;
        vec2 xy = axis - u_radius * (1.0 - cos(theta)) * u_curlDir;
        float z = u_radius * sin(theta);
        pos3 = vec3(xy, z);
        nrm = vec3(-sin(theta) * u_curlDir.x, -sin(theta) * u_curlDir.y, cos(theta));
        v_phase = 1.0;
      } else {
        float backDist = (u_curlDist - PI * u_radius) - along;
        vec2 xy = axis - 2.0 * u_radius * u_curlDir - backDist * u_curlDir;
        pos3 = vec3(xy, 0.0);
        nrm = vec3(0.0, 0.0, -1.0);
        v_phase = 2.0;
      }
      v_uv = a_pos;
      v_normal = nrm;
      vec2 clip = vec2(pos3.x * 2.0 - 1.0, 1.0 - 2.0 * pos3.y / u_aspect);
      gl_Position = vec4(clip, -pos3.z * 0.001, 1.0);
    }
  `;

  const FS_SRC = `
    precision mediump float;
    varying vec2 v_uv;
    varying float v_phase;
    varying vec3 v_normal;
    uniform sampler2D u_tex;
    void main() {
      vec3 lightDir = normalize(vec3(0.25, 0.25, 1.0));
      if (v_phase > 1.5) {
        // back of the page — paper, with a faint mirrored bleed-through of the front
        // (real thin paper lets a hint of the print show through, mirrored)
        vec4 mirror = texture2D(u_tex, vec2(1.0 - v_uv.x, v_uv.y));
        vec3 paper = vec3(0.93, 0.90, 0.83);
        vec3 col = paper * 0.78 + mirror.rgb * 0.22;
        gl_FragColor = vec4(col, 1.0);
        return;
      }
      vec4 color = texture2D(u_tex, v_uv);
      float diffuse = max(dot(v_normal, lightDir), 0.0);
      float light = 0.78 + 0.22 * diffuse;
      gl_FragColor = vec4(color.rgb * light, color.a);
    }
  `;

  function _compile(gl, type, src) {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      console.error("shader:", gl.getShaderInfoLog(sh));
      gl.deleteShader(sh);
      return null;
    }
    return sh;
  }

  function initGL(canvas) {
    const gl = canvas.getContext("webgl", { alpha: true, premultipliedAlpha: false, antialias: true });
    if (!gl) return null;
    const vs = _compile(gl, gl.VERTEX_SHADER, VS_SRC);
    const fs = _compile(gl, gl.FRAGMENT_SHADER, FS_SRC);
    if (!vs || !fs) return null;
    const prog = gl.createProgram();
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      console.error("link:", gl.getProgramInfoLog(prog));
      return null;
    }
    const N = PEEL_GRID;
    const positions = new Float32Array((N + 1) * (N + 1) * 2);
    let k = 0;
    for (let j = 0; j <= N; j++) {
      for (let i = 0; i <= N; i++) {
        positions[k++] = i / N;
        positions[k++] = j / N;
      }
    }
    const indices = new Uint16Array(N * N * 6);
    let m = 0;
    for (let j = 0; j < N; j++) {
      for (let i = 0; i < N; i++) {
        const a = j * (N + 1) + i;
        const b = a + 1;
        const c = a + (N + 1);
        const d = c + 1;
        indices[m++] = a; indices[m++] = b; indices[m++] = c;
        indices[m++] = b; indices[m++] = d; indices[m++] = c;
      }
    }
    const posBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, posBuf);
    gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW);
    const idxBuf = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return {
      gl, prog, posBuf, idxBuf, tex,
      indexCount: indices.length,
      a_pos: gl.getAttribLocation(prog, "a_pos"),
      u_aspect: gl.getUniformLocation(prog, "u_aspect"),
      u_corner: gl.getUniformLocation(prog, "u_corner"),
      u_curlDir: gl.getUniformLocation(prog, "u_curlDir"),
      u_curlDist: gl.getUniformLocation(prog, "u_curlDist"),
      u_radius: gl.getUniformLocation(prog, "u_radius"),
      u_tex: gl.getUniformLocation(prog, "u_tex"),
    };
  }

  function uploadTexture(state, srcCanvas) {
    const { gl, tex } = state;
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, srcCanvas);
  }

  function renderFrame(state, canvas, params) {
    const { gl, prog, posBuf, idxBuf, indexCount, tex } = state;
    gl.viewport(0, 0, canvas.width, canvas.height);
    // transparent clear: page-stack illusion comes from the iframe (already advancing
    // to the new page) showing through the regions exposed behind the curl
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, posBuf);
    gl.enableVertexAttribArray(state.a_pos);
    gl.vertexAttribPointer(state.a_pos, 2, gl.FLOAT, false, 0, 0);
    gl.uniform1f(state.u_aspect, params.aspect);
    gl.uniform2f(state.u_corner, params.corner[0], params.corner[1]);
    gl.uniform2f(state.u_curlDir, params.curlDir[0], params.curlDir[1]);
    gl.uniform1f(state.u_curlDist, params.curlDist);
    gl.uniform1f(state.u_radius, params.radius != null ? params.radius : PEEL_RADIUS);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.uniform1i(state.u_tex, 0);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
    gl.drawElements(gl.TRIANGLES, indexCount, gl.UNSIGNED_SHORT, 0);
  }

  let turning = false;

  // anchor → corner UV + curl direction (in aspect-corrected page space, unnormalized).
  // The aspect-corrected diagonal length is sqrt(1 + aspect²) regardless of which corner.
  const ANCHORS = {
    tr: { corner: [1, 0], dirSign: [-1,  1] },
    tl: { corner: [0, 0], dirSign: [ 1,  1] },
    br: { corner: [1, 1], dirSign: [-1, -1] },
    bl: { corner: [0, 1], dirSign: [ 1, -1] },
  };

  // A peel session owns the WebGL canvas + uploaded texture for one turn (click or drag).
  // render(curlDist) repaints; destroy() removes the canvas. Reused across click/drag paths.
  function startPeelSession(direction, anchor) {
    if (!cachedSnap) return null;
    const useSnap = cachedSnap;
    cachedSnap = null;

    const w = viewerFrame.offsetWidth, h = viewerFrame.offsetHeight;
    const dpr = window.devicePixelRatio || 1;
    const canvas = document.createElement("canvas");
    canvas.className = "peel-canvas";
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.width = w + "px";
    canvas.style.height = h + "px";
    viewerFrame.appendChild(canvas);

    const state = initGL(canvas);
    if (!state) {
      canvas.remove();
      cachedSnap = useSnap;
      return null;
    }
    uploadTexture(state, useSnap);

    const aspect = h / w;
    const a = ANCHORS[anchor];
    const corner = a.corner;
    const dirLen = Math.sqrt(1 + aspect * aspect);
    const curlDir = [a.dirSign[0] / dirLen, (a.dirSign[1] * aspect) / dirLen];
    // maxDist is curlDist when the cursor is at the opposite corner (d = dirLen).
    // With cursor-pinning: curlDist = d · (2π−2)/(π−2)
    const maxDist = dirLen * TWO_PI_MINUS_2 / PI_MINUS_2;

    return {
      canvas, state, useSnap, direction,
      aspect, corner, curlDir, maxDist, dirLen,
      // render({curlDist, curlDir?, radius?}) — radius defaults to the cursor-pinning
      // adaptive value derived from curlDist. Pass an explicit radius (e.g. PEEL_RADIUS)
      // for click animation if you want fixed-tightness curl.
      render(opts) {
        renderFrame(state, canvas, {
          aspect, corner,
          curlDir: (opts && opts.curlDir) || curlDir,
          curlDist: opts.curlDist,
          radius: opts.radius != null ? opts.radius : radiusFromCurlDist(opts.curlDist),
        });
      },
      destroy() { canvas.remove(); },
    };
  }

  function animateSession(session, fromDist, toDist, duration, onDone, lockedCurlDir) {
    const start = performance.now();
    function step(now) {
      const t = Math.min((now - start) / duration, 1);
      const e = easeInOutCubic(t);
      session.render({
        curlDist: fromDist + (toDist - fromDist) * e,
        curlDir: lockedCurlDir,
      });
      if (t < 1) requestAnimationFrame(step);
      else { session.destroy(); if (onDone) onDone(); }
    }
    requestAnimationFrame(step);
  }

  // Spring-driven settle, semi-implicit Euler. Used for drag release: pointer
  // velocity carries through into the spring as initial momentum, so a fast flick
  // commits faster than a slow drag, matching iBooks feel.
  function springSettle(session, fromDist, toDist, initialVel, opts, onDone, lockedCurlDir) {
    const stiffness = opts.stiffness;
    const damping = opts.damping;
    const restEps = 0.0008;
    let pos = fromDist;
    let vel = initialVel;
    let lastT = performance.now();
    function step(now) {
      let dt = (now - lastT) / 1000;
      if (dt > 0.05) dt = 0.05;  // clamp tab-switch gaps
      lastT = now;
      const force = -stiffness * (pos - toDist) - damping * vel;
      vel += force * dt;
      pos += vel * dt;
      session.render({ curlDist: pos, curlDir: lockedCurlDir });
      const settled = Math.abs(pos - toDist) < restEps && Math.abs(vel) < restEps;
      if (settled) {
        session.render({ curlDist: toDist, curlDir: lockedCurlDir });
        session.destroy();
        if (onDone) onDone();
      } else {
        requestAnimationFrame(step);
      }
    }
    requestAnimationFrame(step);
  }

  function turn(direction /* "next" | "prev" */) {
    if (turning) return;
    // buttons + keys default to top corners
    const anchor = direction === "next" ? "tr" : "tl";
    const session = startPeelSession(direction, anchor);
    if (!session) {
      direction === "next" ? rendition.next() : rendition.prev();
      return;
    }
    turning = true;
    direction === "next" ? rendition.next() : rendition.prev();
    animateSession(session, 0, session.maxDist, PEEL_MS, () => { turning = false; });
  }

  // ---- drag-from-corner: pointer-driven curl with cursor-angle-driven direction.
  //
  // curlDir tracks the angle from anchor to cursor (re-normalized each frame), so the
  // fold line rotates as the cursor moves rather than staying perpendicular to a fixed
  // diagonal. This is the visible Apple Books behavior — the curl follows your finger.
  function attachDragZone(el, dir, anchor) {
    let pointerId = null;
    let startX = 0, startY = 0;
    let moved = false;
    let session = null;
    let lastDist = 0;
    let lastDir = null;
    let prevDist = 0;
    let prevTime = 0;
    let velocity = 0;  // curlDist units per second, for spring initial momentum

    el.addEventListener("pointerdown", (e) => {
      if (turning) return;
      pointerId = e.pointerId;
      el.setPointerCapture(pointerId);
      startX = e.clientX;
      startY = e.clientY;
      moved = false;
      session = null;
      lastDist = 0;
      lastDir = null;
      prevDist = 0;
      prevTime = 0;
      velocity = 0;
      e.preventDefault();
    });

    el.addEventListener("pointermove", (e) => {
      if (e.pointerId !== pointerId) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      if (!moved && Math.hypot(dx, dy) < 5) return;
      if (!moved) {
        moved = true;
        session = startPeelSession(dir, anchor);
        if (!session) { pointerId = null; return; }
        turning = true;
        // advance the iframe NOW so the next page is rendering behind the curl as
        // the user drags. revert path will call the inverse if user doesn't commit.
        dir === "next" ? rendition.next() : rendition.prev();
      }
      if (!session) return;

      // cursor in aspect-corrected page space (W is used for both axes)
      const rect = viewerFrame.getBoundingClientRect();
      const W = rect.width;
      const cx = (e.clientX - rect.left) / W;
      const cy = (e.clientY - rect.top) / W;
      // anchor in aspect-corrected (corner UV's y is scaled by aspect)
      const ax = session.corner[0];
      const ay = session.corner[1] * session.aspect;
      const tox = cx - ax;
      const toy = cy - ay;
      const dist = Math.hypot(tox, toy);
      if (dist < 1e-3) {
        session.render({ curlDist: 0 });
        lastDist = 0;
        lastDir = null;
        return;
      }
      const dynDir = [tox / dist, toy / dist];
      // map cursor distance d → curlDist that pins the corner to the cursor
      const curl = Math.min(dist * TWO_PI_MINUS_2 / PI_MINUS_2, session.maxDist);

      // exponentially smooth velocity in cursor-distance units (page UV / sec) so
      // FLICK_VEL stays a human-meaningful threshold regardless of geometry.
      // Convert to curlDist-velocity at release for spring initial momentum.
      const now = performance.now();
      if (prevTime > 0) {
        const dtSec = (now - prevTime) / 1000;
        if (dtSec > 0) {
          const instVel = (dist - prevDist) / dtSec;
          velocity = velocity * 0.5 + instVel * 0.5;
        }
      }
      prevDist = dist;
      prevTime = now;

      lastDist = curl;
      lastDir = dynDir;
      session.render({ curlDist: curl, curlDir: dynDir });
    });

    function end(e) {
      if (e.pointerId !== pointerId) return;
      try { el.releasePointerCapture(pointerId); } catch (_) {}
      const wasMoved = moved;
      const s = session;
      const lockedDir = lastDir;
      pointerId = null;
      moved = false;
      session = null;
      lastDir = null;

      if (!wasMoved) {
        turn(dir);
        return;
      }
      if (!s) return;

      // commit threshold: cursor past 40% of max curl distance, OR a fast outward
      // flick (positive cursor-velocity above a threshold). 3 page-UV/sec is
      // roughly an intentional flick; normal drags max ~2.
      const FLICK_VEL = 3.0;
      const commit = lastDist >= s.maxDist * 0.4 || velocity > FLICK_VEL;
      // velocity is in cursor-distance units; spring animates curlDist, so scale
      const releaseVel = velocity * TWO_PI_MINUS_2 / PI_MINUS_2;
      if (commit) {
        springSettle(s, lastDist, s.maxDist, releaseVel,
          { stiffness: 220, damping: 30 },
          () => { turning = false; }, lockedDir);
      } else {
        cachedSnap = s.useSnap;
        dir === "next" ? rendition.prev() : rendition.next();
        springSettle(s, lastDist, 0, releaseVel,
          { stiffness: 240, damping: 22 },
          () => { turning = false; }, lockedDir);
      }
    }
    el.addEventListener("pointerup", end);
    el.addEventListener("pointercancel", end);
  }

  document.querySelectorAll(".drag-zone").forEach((z) => {
    attachDragZone(z, z.dataset.dir, z.dataset.anchor);
  });

  document.getElementById("prev").addEventListener("click", () => turn("prev"));
  document.getElementById("next").addEventListener("click", () => turn("next"));
  document.addEventListener("keyup", (e) => {
    if (e.key === "ArrowLeft") turn("prev");
    if (e.key === "ArrowRight") turn("next");
  });

  // ---- save reading location (debounced)
  const locLabel = document.getElementById("loc-label");
  let saveTimer = null;
  rendition.on("relocated", (loc) => {
    if (loc && loc.start) {
      locLabel.textContent = `loc ${loc.start.displayed.page}/${loc.start.displayed.total}`;
    }
    // refresh the page snapshot for the next peel; small delay so the iframe paint settles
    setTimeout(refreshSnapshot, 80);
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      if (!loc || !loc.start || !loc.start.cfi) return;
      fetch(LOC_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ cfi: loc.start.cfi }),
      });
    }, 800);
  });

  // ---- highlights: load existing
  function renderHighlight(h) {
    rendition.annotations.add(
      "highlight",
      h.cfi,
      { id: h.id },
      null,
      `hl-${h.color}`,
      { fill: COLOR_HEX[h.color] || COLOR_HEX.yellow, "fill-opacity": "0.4", "mix-blend-mode": "multiply" },
    );
  }

  rendition.started.then(() =>
    fetch(HL_URL)
      .then((r) => r.json())
      .then((rows) => rows.forEach(renderHighlight))
      .catch(() => { /* no highlights yet — fine */ })
      .finally(() => { window.__hlLoaded = true; })
  );

  // ---- selection → popup
  const popup = document.getElementById("hl-popup");
  const noteEl = document.getElementById("hl-note");
  const tagsEl = document.getElementById("hl-tags");
  const swatches = popup.querySelectorAll(".swatch");
  let pending = null; // { cfi, text, color }

  function setColor(c) {
    pending.color = c;
    swatches.forEach((s) => s.classList.toggle("selected", s.dataset.color === c));
  }
  swatches.forEach((s) => s.addEventListener("click", () => setColor(s.dataset.color)));

  function showPopup(clientX, clientY) {
    popup.hidden = false;
    // clamp to viewport
    const w = popup.offsetWidth;
    const h = popup.offsetHeight;
    const x = Math.min(clientX, window.innerWidth - w - 12);
    const y = Math.min(clientY, window.innerHeight - h - 12);
    popup.style.left = `${Math.max(8, x)}px`;
    popup.style.top  = `${Math.max(8, y)}px`;
  }

  function hidePopup() {
    popup.hidden = true;
    pending = null;
    noteEl.value = "";
    tagsEl.value = "";
  }

  rendition.on("selected", (cfiRange, contents) => {
    book.getRange(cfiRange).then((range) => {
      const text = range.toString().trim();
      if (!text) return;
      pending = { cfi: cfiRange, text, color: "yellow" };
      setColor("yellow");

      // position popup near the iframe-relative selection
      const sel = contents.window.getSelection();
      let cx = window.innerWidth / 2;
      let cy = 80;
      if (sel && sel.rangeCount) {
        const rect = sel.getRangeAt(0).getBoundingClientRect();
        const iframe = contents.document.defaultView.frameElement;
        const off = iframe ? iframe.getBoundingClientRect() : { left: 0, top: 0 };
        cx = off.left + rect.left;
        cy = off.top + rect.bottom + 8;
      }
      showPopup(cx, cy);
    });
  });

  document.getElementById("hl-cancel").addEventListener("click", hidePopup);

  document.getElementById("hl-save").addEventListener("click", () => {
    if (!pending) return;
    const tags = tagsEl.value.split(",").map((t) => t.trim()).filter(Boolean);
    const body = {
      cfi: pending.cfi,
      text: pending.text,
      color: pending.color,
      note: noteEl.value.trim() || null,
      tags,
    };
    fetch(POST_HL_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    })
      .then((r) => {
        if (!r.ok) throw new Error(`save failed: ${r.status}`);
        return r.json();
      })
      .then((h) => {
        renderHighlight(h);
        hidePopup();
      })
      .catch((err) => {
        alert(err.message);
      });
  });
})();
