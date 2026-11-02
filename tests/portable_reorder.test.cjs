const test = require('node:test');
const assert = require('node:assert/strict');
const re = require('../services/PortableReorder.js');

function sample() {
    return {
        slots: [1, 2, 3],
        identities: [2, 1, 3],
        clients: [
            {address:'0xabc', workspace:{id:1}, grouped:[], fullscreen:0, fullscreenClient:0, pinned:false, pseudo:false},
            {address:'0xdef', workspace:{id:2}, grouped:[], fullscreen:0, fullscreenClient:0, pinned:false, pseudo:false}
        ],
        workspaces: [{id:1,monitor:'DP-1'}, {id:2,monitor:'DP-1'}],
        rules: []
    };
}

test('reorder maps real desktop identities to target numeric IDs', () => {
    const x=sample();
    const p=re.plan(x.slots, x.identities, x.clients, x.workspaces, x.rules);
    assert.deepEqual(p.mapping, {'1':2, '2':1});
    assert.equal(p.first.length, 2);
    assert.deepEqual(p.second.map(m=>m.target), [2,1]);
    assert.notEqual(p.first[0].target, p.first[1].target);
    assert.ok(p.first.every(m => m.target > 3));
    assert.deepEqual(p.recovery.map(m=>m.target), [1,2]);
    const first=p.rows.map(r=>({address:r.address,workspace:{id:r.temporary}}));
    const second=p.rows.map(r=>({address:r.address,workspace:{id:r.destination}}));
    assert.equal(re.checkClients(first,p.rows,'first'),true);
    assert.equal(re.checkClients(second,p.rows,'second'),true);
    assert.equal(re.checkClients(second,p.rows,'first'),false);
});

test('provider detects both config formats and refuses unknown modes', () => {
    assert.equal(re.provider('configProvider: lua','Hyprland 0.56.2'),'lua');
    assert.equal(re.provider('configProvider: hyprlang','Hyprland 0.56.2'),'legacy');
    assert.equal(re.provider('','Hyprland 0.54.0'),'legacy');
    assert.throws(()=>re.provider('','Hyprland 0.56.2'),/cannot identify/);
});

test('commands dispatch to the intended window without using config writes', () => {
    const move={address:'0xabc',target:2};
    assert.match(re.dispatch(move,'lua'),/hl\.dsp\.window\.move/);
    assert.match(re.dispatch(move,'legacy'),/movetoworkspacesilent/);
    assert.match(re.batch([move],'lua'),/set -e/);
    assert.doesNotMatch(re.batch([move],'lua'),/rules\.lua|reload|python3/);
    assert.throws(()=>re.dispatch({address:'0xabc;rm -rf',target:2},'lua'),/unsafe/);
    assert.throws(()=>re.dispatch({address:'0xabc',target:0},'legacy'),/unsafe/);
});

test('refuses ambiguous or destructive permutations', () => {
    assert.throws(()=>re.permutation([1,1],[1,2]),/same unique/);
    assert.throws(()=>re.permutation([1,2],[1,3]),/same unique/);
    assert.throws(()=>re.permutation([0,2],[0,2]),/same unique/);
    assert.throws(()=>re.permutation([-1,2],[-1,2]),/same unique/);
});

test('rejects pinned workspace placements before any dispatch', () => {
    const x=sample();
    assert.throws(()=>re.plan(x.slots,x.identities,x.clients,x.workspaces,
        [{workspaceString:'1', monitor:'DP-1'}]),/rule may pin/);
    assert.throws(()=>re.plan(x.slots,x.identities,x.clients,x.workspaces,
        [{workspaceString:'r[1-10]'}]),/rule may pin/);
    assert.doesNotThrow(()=>re.plan(x.slots,x.identities,x.clients,x.workspaces,
        [{workspaceString:'20', monitor:'DP-1'}]));
});

test('rejects complex clients and cross-monitor permutations', () => {
    const x=sample();
    x.clients[0].grouped=['0xbeef'];
    assert.throws(()=>re.plan(x.slots,x.identities,x.clients,x.workspaces,x.rules),/grouped/);
    x.clients[0].grouped=[];
    x.workspaces[1].monitor='HDMI-A-1';
    assert.throws(()=>re.plan(x.slots,x.identities,x.clients,x.workspaces,x.rules),/cross-monitor/);
});

test('no client moves are generated for empty desktops', () => {
    const x=sample();
    const p=re.plan(x.slots,x.identities,[],x.workspaces,x.rules);
    assert.equal(p.rows.length,0);
    assert.deepEqual(p.mapping, {'1':2,'2':1});
});

test('read-only clone has packaged palette and no hard-coded owner account', () => {
    const fs=require('node:fs');
    const path=require('node:path');
    const root=path.join(__dirname,'..');
    const colors=fs.readFileSync(path.join(root,'common/Appearance.colors.qml'),'utf8');
    assert.match(colors,/m3background/);
    const runtimeFiles=[
        'shell.qml','common/Appearance.qml','common/Config.qml',
        'services/DesktopMetadata.qml','services/WorkspaceReorder.qml'
    ];
    for (const file of runtimeFiles) {
        const source=fs.readFileSync(path.join(root,file),'utf8');
        assert.doesNotMatch(source,/\/home\/reason|\/modules\/rules\.lua/);
    }
    const r=fs.readFileSync(path.join(root,'services/WorkspaceReorder.qml'),'utf8');
    assert.doesNotMatch(r,/workspace_reorder\.py|python3|luac|hyprctl reload/);
});
