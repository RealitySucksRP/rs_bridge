RegisterCommand('rsbridgetest', function(source)
    local src = source

    print('Framework:', exports.rs_bridge:GetFramework())
    print('Citizen ID:', exports.rs_bridge:GetCitizenId(src))

    exports.rs_bridge:AddMoney(src, 'bank', 100, 'bridge_test')
    exports.rs_bridge:AddItem(src, 'water_bottle', 1)
    exports.rs_bridge:Notify(src, 'Bridge test complete.', 'success')
end)
