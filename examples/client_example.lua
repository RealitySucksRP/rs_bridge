RegisterCommand('rsbridgeclient', function()
    print('Framework:', exports.rs_bridge:GetFramework())
    print('Job:', json.encode(exports.rs_bridge:GetJob()))

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        print('Fuel:', exports.rs_bridge:GetFuel(veh))
    end

    exports.rs_bridge:Notify('Bridge client test complete.', 'success')
end)
