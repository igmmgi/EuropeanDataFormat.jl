# Documentation

This directory contains the documentation for the EuropeanDataFormat package.

## Building Locally

To build the documentation locally:

```bash
# Build documentation
julia --project=. docs/make.jl
```

The built documentation will be available in `docs/build/`.

## Viewing Locally

After building, you can view the documentation by opening `docs/build/index.html` in your web browser.

## Structure

- `src/` - Source markdown files
- `make.jl` - Documenter configuration
- `build/` - Generated HTML documentation (after building)

## Pages

- **Home** (`index.md`) - Overview and quick start guide
- **API Reference** (`api.md`) - Complete function and type documentation
- **Examples** (`examples.md`) - Practical usage examples

## Deployment

The documentation is automatically deployed to GitHub Pages via GitHub Actions when:
- Code is pushed to the `main` branch
- A new version tag is created

## Customization

To modify the documentation:
1. Edit the markdown files in `src/`
2. Update `make.jl` if you need to change the build configuration
3. Rebuild with `julia --project=docs/ docs/make.jl`
