# FS25_VariableBunker

VariableBunker is a configurable three-sided bunker silo for Farming Simulator 25. Its simple concrete side and rear walls and all functional areas adapt to the selected dimensions in the construction menu.

## Configurations

- Interior width: 6–20 m in 1 m steps, then 25–100 m in 5 m steps
- Length: 20–50 m in 5 m steps, then 60–200 m in 10 m steps
- Wall height: 2–8 m in 1 m steps
- Default: 10 × 40 × 4 m

The purchase price is independent of the selected size. The silo accepts chaff, grass windrows and dry grass windrows and ferments them into silage. The front remains open while a full-width concrete wall closes the rear. All walls remain vertical on the inside; above a 0.5 m vertical base, their outside face slopes inward at a constant angle so taller walls receive a wider base.

The concrete floor slab is optional and offers two sizes: flush with the open front or extended 30 m beyond it. It spans the complete outside width including the height-dependent wall bases. The extended slab provides a smooth blade transition and makes the required AutoDrive approach area visible during placement. The slab is disabled by default. All visible concrete uses the original GIANTS bunker diffuse, gloss, dirt and moss material through game-data references.

When AutoDrive is active in the current savegame, the construction menu includes an optional AutoDrive course. Without AutoDrive the complete course option remains hidden and the bunker works independently. When enabled, placing the bunker creates one parallel drive lane per approximately 5 m of interior width, cross-connections and one destination marker per lane. Following the reference course, every lane ends 3.2 m before the rear wall and extends 27 m beyond the open front. The course adapts to the configured width and length and reaches 20 lanes at 100 m width; it remains disabled by default. Detection does not depend on a specific AutoDrive version, and both the current placement API and its older event API are supported.

## Development

The mod is built and validated only through `C:\FS25\main\Source\Build\Build-VariableBunker.ps1`. The build checks the configuration ranges, I3D mappings, runtime scaling logic, ZIP paths and the GIANTS TestRunner result before deployment.

## License

See [LICENSE](LICENSE).
