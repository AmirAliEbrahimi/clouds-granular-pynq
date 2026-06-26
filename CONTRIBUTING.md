# Contributing

Thanks for your interest in improving this project. Contributions of bug
reports, fixes, tests, and features are welcome.

## Development setup

You only need [Icarus Verilog](http://iverilog.icarus.com/) to run the suite:

```sh
make test     # all functional testbenches, including the serdes loopback
```

Please make sure it passes before opening a pull request.

## Coding standards

- **Synthesizable RTL in `rtl/` is strict Verilog-2001.** No SystemVerilog
  constructs there (`logic`, `always_ff`, `typedef enum`, `$clog2`, typed
  `parameter int`, etc.). Testbenches under `sim/` may use SystemVerilog.
- Keep the design **timing-closed at 100 MHz** on the XC7Z020. New multipliers
  should have registered inputs and a registered output so they map cleanly to
  DSP48 slices.
- Prefer adding a pipeline stage over lengthening a combinational path as the
  per-sample FSM has a large cycle budget (~2048 clocks/sample).
- Match the existing naming and header-comment style; document any non-obvious
  fixed-point scaling.

## Tests

- Every behavioural change to the engine should keep the existing testbenches
  passing, and ideally add a check.
- If you change `iis_deser.v`/`iis_ser.v`, the `tb_iis_loopback` round-trip must
  still pass.

## Pull requests

1. Fork and create a topic branch.
2. Keep changes focused; describe the *why* in the PR.
3. Confirm `make test` passes and note any timing impact.
4. Sign off your commits (`git commit -s`) to certify the
   [Developer Certificate of Origin](https://developercertificate.org/).

## Reporting bugs

Open an issue with: board/tooling versions, what you observed vs expected, and
(for RTL) a minimal waveform or testbench that reproduces it.
