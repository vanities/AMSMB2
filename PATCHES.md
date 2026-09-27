# Earmark / Mango maintenance patch

Based on upstream AMSMB2 4.0.3. This fork keeps the upstream license and API.

A network timeout returned from `wait_for_reply` while libsmb2 still retained a pointer
to callback state on the Swift stack. Servicing a delayed response during reconnect
then crashed in `SMB2Client.generic_handler`.

Keep the callback pointer valid throughout the wait and destroy a failed context before
that scope exits. The next `connectShare` creates a fresh connection. Successful requests
and SMB error replies keep their existing behavior.

`TimeoutRecoveryTests` reproduces the old crash with a disposable Docker SMB fixture,
then verifies reconnect, directory listing and ranged reads after both echo and file-open
timeouts. Debug and optimized builds exercise the same lifetime rules.

The opt-in fixture listens at localhost:1446, share `qa`, test login `qa` / `fixture-only`,
and contains `AudioMoved/Network Endurance.wav` (any valid WAV). Mount generated files
read-only. Name the disposable container `library-endurance-qa-smb` and run:

```
SMB_TIMEOUT_TEST_CONTAINER=library-endurance-qa-smb swift test --filter TimeoutRecoveryTests
SMB_TIMEOUT_TEST_CONTAINER=library-endurance-qa-smb swift test -c release --filter TimeoutRecoveryTests
```

The tests pause and unpause only a container explicitly named with the
`library-endurance-qa-` prefix. Do not point them at a server used for other work.
