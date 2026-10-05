# Integration tests need a live DICOM server; run with `mix test --include integration`
ExUnit.start(exclude: [:integration])
