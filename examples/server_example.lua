RegisterCommand('rsbridgetest', function(source)
    local src = source

    print('Framework:', exports.rs_bridge:GetFramework())
    print('Citizen ID:', exports.rs_bridge:GetCitizenId(src))
    print('Inventory item count water_bottle:', exports.rs_bridge:GetItemCount(src, 'water_bottle'))

    exports.rs_bridge:AddMoney(src, 'bank', 100, 'bridge_test')
    exports.rs_bridge:AddItem(src, 'water_bottle', 1)
    exports.rs_bridge:Notify(src, 'Bridge server test complete.', 'success')
end)
