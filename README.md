# FS25_VariableBunker

VariableBunker is a configurable drive-through bunker silo for Farming Simulator 25. Its simple concrete walls and all functional areas adapt to the selected dimensions in the construction menu.

## Configurations

- Interior width: 6–20 m in 1 m steps
- Length: 20–50 m in 5 m steps, plus 60, 70 and 80 m
- Wall height: 2–6 m in 1 m steps
- Default: 10 × 40 × 4 m

The purchase price is independent of the selected size. The silo accepts chaff, grass windrows and dry grass windrows and ferments them into silage. Both ends remain open, matching the base-game drive-through bunker silos.

## Development

The mod is built and validated only through `C:\FS25\main\Source\Build\Build-VariableBunker.ps1`. The build checks the configuration ranges, I3D mappings, runtime scaling logic, ZIP paths and the GIANTS TestRunner result before deployment.

## License

See [LICENSE](LICENSE).
