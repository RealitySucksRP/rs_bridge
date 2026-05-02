RegisterCommand('rsbridgeclient', function()
    print('Framework:', exports.rs_bridge:GetFramework())
    print('Job:', json.encode(exports.rs_bridge:GetJob()))

    exports.rs_bridge:Notify('Client bridge test complete.', 'success')
end)
