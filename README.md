# EuropeanDataFormat

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://igmmgi.github.io/EuropeanDataFormat.jl/)
[![Build Status](https://github.com/igmmgi/EuropeanDataFormat.jl/workflows/Documentation/badge.svg)](https://github.com/igmmgi/EuropeanDataFormat.jl/actions)
[![CI](https://github.com/igmmgi/EuropeanDataFormat.jl/workflows/Tests/badge.svg)](https://github.com/igmmgi/EuropeanDataFormat.jl/actions)

Julia code for European Data Format (EDF/EDF+) EEG files. See [edfplus.info](https://www.edfplus.info/) for more information about the format. The code can be used for:

- reading files into Julia data struct
- cropping file length
- reducing the sample rate
- selecting/reducing the number of channels
- writing a Julia data struct to a edf fileformat

## Installation

```julia
] # julia pkg manager
add EuropeanDataFormat
# add https://github.com/igmmgi/EuropeanDataFormat.jl.git # install from  GitHub
# test EuropeanDataFormat # optional
```

## Functions

- crop_edf
- downsample_edf
- merge_edf
- select_channels_edf
- read_edf
- write_edf

## Basic Example

```julia
using EuropeanDataFormat

dat1 = read_edf("filename1.edf")
dat2 = read_edf("filename2.edf")
dat3 = merge_edf([dat1, dat2])
write_edf(dat3, "filename3.edf")

```
