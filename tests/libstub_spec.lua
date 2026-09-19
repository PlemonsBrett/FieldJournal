local function test_libstub_exposes_new_and_get_library()
    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")
    assert(type(LibStub) == "table", "LibStub global was not created")
    assert(type(LibStub.NewLibrary) == "function", "LibStub.NewLibrary is missing")
    assert(type(LibStub.GetLibrary) == "function", "LibStub.GetLibrary is missing")

    local lib = LibStub:NewLibrary("FieldJournalTest-1.0", 1)
    assert(type(lib) == "table", "NewLibrary did not return a table for a fresh library")
    assert(LibStub:GetLibrary("FieldJournalTest-1.0") == lib,
        "GetLibrary did not return the same table NewLibrary created")
end

return {
    test_libstub_exposes_new_and_get_library = test_libstub_exposes_new_and_get_library,
}
