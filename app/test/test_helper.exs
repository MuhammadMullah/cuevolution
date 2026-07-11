ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Cuevolution.Repo, :manual)

# Default stub so tests that don't care about SMS specifics just get a
# silent success, matching the "in test env return :ok" requirement —
# individual tests can still override with `expect/3` for failure-path
# assertions.
Mox.stub(Cuevolution.Notifications.SmsAdapter.SmsAdapterMock, :send, fn _mobile_number, _body ->
  {:ok, %{}}
end)
