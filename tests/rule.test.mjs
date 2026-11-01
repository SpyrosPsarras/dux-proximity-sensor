import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../rule.js", import.meta.url), "utf8").replace(".pragma library", "");
const Rule = new Function(source + "\nreturn { group, device, isComplete, devices, isMet, isNear, strongestSignal, prune, nodeAt, replaceAt };")();

const phone = { ...Rule.device("aa:aa:aa:aa:aa:aa", "Phone") };
const watch = { ...Rule.device("BB:BB:BB:BB:BB:BB", "Watch"), check: "signal", minSignal: -70 };
const buds = Rule.device("CC:CC:CC:CC:CC:CC", "Buds");
const groupOf = (need, ...items) => ({ ...Rule.group(need), items });
const near = (...names) => node => names.includes(node.name);

test("device addresses are stored upper case", () => {
    assert.equal(phone.address, "AA:AA:AA:AA:AA:AA");
});

test("all, any and exactly one", () => {
    const all = groupOf("all", phone, watch);
    const any = groupOf("any", phone, watch);
    const one = groupOf("one", phone, watch);
    for (const [present, a, b, c] of [[[], false, false, false], [["Phone"], false, true, true], [["Phone", "Watch"], true, true, false]]) {
        assert.equal(Rule.isMet(all, near(...present)), a, `all ${present}`);
        assert.equal(Rule.isMet(any, near(...present)), b, `any ${present}`);
        assert.equal(Rule.isMet(one, near(...present)), c, `one ${present}`);
    }
});

test("exactly one with three items means one, not an odd count", () => {
    assert.equal(Rule.isMet(groupOf("one", phone, watch, buds), near("Phone", "Watch", "Buds")), false);
});

test("nested groups: phone with (watch or buds)", () => {
    const rule = groupOf("all", phone, groupOf("any", watch, buds));
    assert.equal(Rule.isMet(rule, near("Phone", "Buds")), true);
    assert.equal(Rule.isMet(rule, near("Watch", "Buds")), false);
});

test("an empty all group is met but incomplete", () => {
    const empty = Rule.group("all");
    assert.equal(Rule.isMet(empty, near()), true);
    assert.equal(Rule.isComplete(empty), false);
});

test("an empty group anywhere makes the rule incomplete", () => {
    assert.equal(Rule.isComplete(groupOf("any")), false);
    assert.equal(Rule.isComplete(groupOf("any", phone, groupOf("all"))), false);
    assert.equal(Rule.isComplete(groupOf("all", phone, groupOf("any", watch, groupOf("any")))), false);
    assert.equal(Rule.isComplete(groupOf("any", phone, groupOf("all", watch))), true);
    assert.equal(Rule.isComplete(null), false);
});

test("connected check reads the connected map", () => {
    assert.equal(Rule.isNear(phone, { connected: { "AA:AA:AA:AA:AA:AA": true } }, 0, 1000), true);
    assert.equal(Rule.isNear(phone, { connected: {} }, 0, 1000), false);
});

test("signal check needs a strong enough reading inside the timeout", () => {
    const live = { samples: { "BB:BB:BB:BB:BB:BB": [[1000, -80], [5000, -65]] } };
    assert.equal(Rule.isNear(watch, live, 6000, 2000), true);
    assert.equal(Rule.isNear(watch, live, 8000, 2000), false, "reading too old");
    assert.equal(Rule.isNear({ ...watch, minSignal: -60 }, live, 6000, 2000), false, "reading too weak");
    assert.equal(Rule.isNear(watch, { samples: {} }, 6000, 2000), false);
});

test("prune drops old readings and empty devices", () => {
    const kept = Rule.prune({ A: [[1, -50], [10, -60]], B: [[1, -50]] }, 12, 5);
    assert.deepEqual(kept, { A: [[10, -60]] });
});

test("nodeAt finds roots and nested nodes, and tolerates removed paths", () => {
    const rule = groupOf("all", phone, groupOf("any", watch, buds));
    assert.equal(Rule.nodeAt(rule, []), rule);
    assert.equal(Rule.nodeAt(rule, [0]), phone);
    assert.equal(Rule.nodeAt(rule, [1]), rule.items[1]);
    assert.equal(Rule.nodeAt(rule, [1, 0]), watch);
    assert.equal(Rule.nodeAt(rule, [2]), undefined);
    assert.equal(Rule.nodeAt(rule, [2, 0]), undefined);
    assert.equal(Rule.nodeAt(rule, [0, 0]), undefined);
    assert.equal(Rule.nodeAt(null, [0]), undefined);
});

test("replaceAt edits and removes without touching the original", () => {
    const rule = groupOf("all", phone, groupOf("any", watch, buds));
    const edited = Rule.replaceAt(rule, [1, 0], { ...watch, minSignal: -50 });
    assert.equal(edited.items[1].items[0].minSignal, -50);
    assert.equal(rule.items[1].items[0].minSignal, -70);
    const removed = Rule.replaceAt(rule, [1, 1], null);
    assert.deepEqual(removed.items[1].items.map(i => i.name), ["Watch"]);
    assert.deepEqual(Rule.devices(rule).map(d => d.name), ["Phone", "Watch", "Buds"]);
});
