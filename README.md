# FS25_VariableBunker

VariableBunker is a configurable bunker or drive-through silo for Farming Simulator 25. Its simple concrete walls and all functional areas adapt to the selected dimensions in the construction menu.

## Configurations

- Interior width: 6–20 m in 1 m steps, then 25–100 m in 5 m steps
- Length: 20–50 m in 5 m steps, then 60–200 m in 10 m steps
- Wall height: 2–8 m in 1 m steps
- Default: 10 × 40 × 4 m

The purchase price is independent of the selected size. The silo accepts chaff, grass windrows and dry grass windrows and ferments them into silage. The front remains open while a full-width concrete wall closes the rear. All walls remain vertical on the inside; above a 1.5 m vertical base, their outside face slopes inward at a constant angle so taller walls receive a wider base.

The silo design is selectable: the bunker silo has a rear wall, while the drive-through silo is open at both ends. The straight outside wall base is 1.5 m high; dedicated corner bases and corner wedges join the trimmed side and rear slopes without intersections or projecting tips. The concrete floor slab is optional. It can end flush with the silo, or extend 30 m beyond the bunker entrance. For a drive-through silo, the extended slab reaches 30 m beyond the rear and 15 m beyond the front. It spans the complete outside width including the height-dependent wall bases. All visible concrete uses the original GIANTS `concreteGeneric` diffuse, normal and specular maps through `$data` game-data references. The GIANTS `vertexPaintShader` projects the texture triplanar in world space at a constant two-metre tile size, so runtime dimensions no longer stretch the concrete pattern.

When AutoDrive is active in the current savegame, the construction menu includes an optional AutoDrive course. Without AutoDrive the complete course option remains hidden and the silo works independently. When enabled, the bunker design reproduces the BGA reference topology with destinations 3.2 m before the rear wall and the detailed connection clusters 4 m and 26 m beyond the open front. The drive-through design reproduces the large-silo reference with one-way lanes extending 10 m and 24 m beyond its open ends. Both graphs adapt to the configured width and length and reach 20 lanes at 100 m width. Courses are created only for a newly placed silo with the option enabled; saved global AutoDrive nodes are never duplicated during savegame loading.

## Development

The mod is built and validated only through `C:\FS25\main\Source\Build\Build-VariableBunker.ps1`. The build checks the configuration ranges, I3D mappings, runtime scaling logic, ZIP paths and the GIANTS TestRunner result before deployment.

## License

See [LICENSE](LICENSE).
