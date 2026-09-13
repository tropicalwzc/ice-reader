(() => {
    "use strict";
    const supported = new Set(["txt", "text", "md", "markdown", "html", "htm"]);
    const maxSize = 200 * 1024 * 1024;
    let token = "", queue = [], failed = [], cancelled = false, activeRequest = null, uploading = false;
    const $ = id => document.getElementById(id);
    const safePath = value => value.replaceAll("\\", "/").split("/").filter(p => p && p !== "." && p !== "..").join("/").slice(0, 1024);
    const extension = name => (name.split(".").pop() || "").toLowerCase();
    const formatBytes = bytes => bytes < 1024 * 1024 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1024 / 1024).toFixed(1)} MB`;

    async function connect() {
        $("pairStatus").textContent = "正在验证…";
        try {
            const response = await fetch("/api/session", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code: $("code").value.trim() }) });
            const body = await response.json();
            if (!response.ok) throw new Error(body.error || "连接失败");
            token = body.token;
            $("pair").classList.add("hidden");
            $("upload").classList.remove("hidden");
        } catch (error) { $("pairStatus").textContent = error.message + "。请检查验证码和设备页面。"; }
    }

    function addFiles(files) {
        let skipped = 0, previousCount = queue.length;
        for (const file of files) {
            const relativePath = safePath(file.webkitRelativePath || file.relativePath || file.name);
            if (!supported.has(extension(file.name)) || file.size > maxSize || file.size === 0) { skipped++; continue; }
            queue.push({ file, relativePath, status: "waiting" });
        }
        const total = queue.reduce((sum, item) => sum + item.file.size, 0);
        $("summary").textContent = `已排队 ${queue.length} 个文件，共 ${formatBytes(total)}${skipped ? `；跳过 ${skipped} 个不支持、空白或过大的文件` : ""}`;
        $("start").disabled = queue.length === 0;
        if (queue.length > previousCount && !uploading) {
            $("current").textContent = "已发现可上传的小说，正在自动开始…";
            window.setTimeout(start, 0);
        }
    }

    function readEntries(reader) {
        return new Promise((resolve, reject) => {
            const all = [];
            const next = () => reader.readEntries(entries => entries.length ? (all.push(...entries), next()) : resolve(all), reject);
            next();
        });
    }

    async function walk(entry, prefix = "") {
        if (entry.isFile) return new Promise((resolve, reject) => entry.file(file => { file.relativePath = prefix + file.name; resolve([file]); }, reject));
        if (!entry.isDirectory) return [];
        const entries = await readEntries(entry.createReader());
        const nested = await Promise.all(entries.map(child => walk(child, `${prefix}${entry.name}/`)));
        return nested.flat();
    }

    function upload(item, completedBytes, totalBytes) {
        return new Promise((resolve, reject) => {
            const query = new URLSearchParams({ filename: item.file.name, relativePath: item.relativePath });
            const request = new XMLHttpRequest();
            activeRequest = request;
            request.open("PUT", `/api/upload?${query}`);
            request.setRequestHeader("Authorization", `Bearer ${token}`);
            request.setRequestHeader("Content-Type", "application/octet-stream");
            request.upload.onprogress = event => {
                if (event.lengthComputable) {
                    $("totalProgress").value = totalBytes ? (completedBytes + event.loaded) / totalBytes : 0;
                    $("current").textContent = `正在上传 ${item.relativePath}：${Math.round(event.loaded / event.total * 100)}%`;
                }
            };
            request.onload = () => {
                activeRequest = null;
                let body = {}; try { body = JSON.parse(request.responseText); } catch (_) {}
                request.status >= 200 && request.status < 300 ? resolve(body) : reject(new Error(body.error || `HTTP ${request.status}`));
            };
            request.onerror = () => { activeRequest = null; reject(new Error("网络连接中断，请保持设备页面在前台后重试")); };
            request.onabort = () => { activeRequest = null; reject(new Error("已取消")); };
            request.send(item.file);
        });
    }

    async function start() {
        if (uploading || !token) return;
        const batch = queue.filter(item => item.status === "waiting");
        if (batch.length === 0) return;
        uploading = true;
        cancelled = false; failed = []; $("results").replaceChildren(); $("start").disabled = true; $("cancel").disabled = false; $("retry").classList.add("hidden");
        const total = batch.reduce((sum, item) => sum + item.file.size, 0); let completed = 0;
        for (const item of batch) {
            if (cancelled) break;
            const li = document.createElement("li"); li.textContent = item.relativePath; $("results").append(li);
            try { await upload(item, completed, total); item.status = "done"; li.className = "ok"; li.textContent += " — 已导入"; }
            catch (error) { item.status = "failed"; failed.push(item); li.className = "error"; li.textContent += ` — ${error.message}`; }
            completed += item.file.size; $("totalProgress").value = total ? completed / total : 0;
        }
        queue = queue.filter(item => item.status === "waiting");
        uploading = false;
        $("cancel").disabled = true; $("start").disabled = queue.length === 0; $("retry").classList.toggle("hidden", failed.length === 0);
        $("current").textContent = cancelled ? "已取消；未完成文件可重新选择或重试。" : `完成：成功 ${$("results").querySelectorAll(".ok").length}，失败 ${failed.length}`;
        if (!cancelled && queue.length > 0) window.setTimeout(start, 0);
    }

    $("connect").addEventListener("click", connect);
    $("code").addEventListener("keydown", event => { if (event.key === "Enter") connect(); });
    $("files").addEventListener("change", event => { addFiles(event.target.files); event.target.value = ""; });
    $("directory").addEventListener("change", event => { addFiles(event.target.files); event.target.value = ""; });
    $("start").addEventListener("click", start);
    $("cancel").addEventListener("click", () => { cancelled = true; activeRequest?.abort(); });
    $("retry").addEventListener("click", () => { queue = failed.map(item => ({ ...item, status: "waiting" })); start(); });
    const zone = $("dropZone");
    ["dragenter", "dragover"].forEach(type => zone.addEventListener(type, event => { event.preventDefault(); zone.classList.add("dragging"); }));
    ["dragleave", "drop"].forEach(type => zone.addEventListener(type, event => { event.preventDefault(); zone.classList.remove("dragging"); }));
    zone.addEventListener("drop", async event => {
        const items = [...event.dataTransfer.items];
        const entries = items.map(item => item.webkitGetAsEntry?.()).filter(Boolean);
        if (entries.length) addFiles((await Promise.all(entries.map(entry => walk(entry)))).flat());
        else addFiles(event.dataTransfer.files);
    });
})();
