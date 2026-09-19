local function test_callbackhandler_new_registers_apis_and_fires()
    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")

    local CallbackHandler = LibStub:GetLibrary("CallbackHandler-1.0")
    assert(CallbackHandler, "CallbackHandler-1.0 was not registered with LibStub")

    local target = {}
    local registry = CallbackHandler:New(target)
    assert(type(target.RegisterCallback) == "function", "New() did not add RegisterCallback to target")

    local fired = false
    target:RegisterCallback("TestEvent", function() fired = true end)
    registry:Fire("TestEvent")
    assert(fired, "registry:Fire did not invoke the registered callback")
end

return {
    test_callbackhandler_new_registers_apis_and_fires = test_callbackhandler_new_registers_apis_and_fires,
}
