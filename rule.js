.pragma library

function group(need) {
    return { kind: "group", need: need, items: [] };
}

function device(address, name) {
    return { kind: "device", address: address.toUpperCase(), name: name || address, check: "connected", minSignal: -70 };
}

function isComplete(node) {
    if (!node)
        return false;
    if (node.kind === "device")
        return !!node.address;
    return Array.isArray(node.items) && node.items.length > 0 && node.items.every(isComplete);
}

function devices(node) {
    if (!node)
        return [];
    if (node.kind === "device")
        return [node];
    return (node.items || []).reduce((all, item) => all.concat(devices(item)), []);
}

function isMet(node, isNear) {
    if (node.kind === "device")
        return isNear(node);
    const count = node.items.filter(item => isMet(item, isNear)).length;
    if (node.need === "all")
        return count === node.items.length;
    if (node.need === "one")
        return count === 1;
    return count > 0;
}

// live.connected: address -> true; live.samples: address -> [[ms, rssi], ...]
function isNear(node, live, now, timeoutMs) {
    if (node.check === "signal")
        return strongestSignal(node.address, live, now, timeoutMs) >= node.minSignal;
    return (live.connected || {})[node.address] === true;
}

function strongestSignal(address, live, now, timeoutMs) {
    const recent = ((live.samples || {})[address] || []).filter(s => now - s[0] <= timeoutMs);
    return recent.length ? Math.max(...recent.map(s => s[1])) : -Infinity;
}

function prune(samples, now, keepMs) {
    const kept = {};
    for (const address in samples) {
        const recent = samples[address].filter(s => now - s[0] <= keepMs);
        if (recent.length)
            kept[address] = recent;
    }
    return kept;
}

function nodeAt(rule, path) {
    return path.reduce((node, i) => node?.items?.[i], rule);
}

// A null replacement removes the node.
function replaceAt(node, path, replacement) {
    if (path.length === 0)
        return replacement;
    const items = node.items.slice();
    const next = replaceAt(items[path[0]], path.slice(1), replacement);
    if (next === null)
        items.splice(path[0], 1);
    else
        items[path[0]] = next;
    return Object.assign({}, node, { items: items });
}
