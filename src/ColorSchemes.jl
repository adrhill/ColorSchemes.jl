#!/usr/bin/env julia

"""
A colorscheme is an array of colors. To use the package:

```
using ColorSchemes, Colors
```

and, if you want image input and output:

```
using Images, FileIO
```

The names of the registered (built-in) colorschemes are listed in the `schemes` array.

To use one of the built-in colorschemes, use its symbol:

```
julia> ColorSchemes.picasso
```

or import it:

```
julia> import ColorSchemes.pigeon
julia> pigeon
```

## Functions:

```
colorscheme_weighted(cscheme::Vector{C}, weights, l = 50) where {C <: Colorant}
```

- return a weighted colorscheme, given a colorscheme and an array of weights for each entry

```
colorscheme_to_image(cs::Vector{C}, nrows=50, tilewidth=5) where {C <: Colorant}
```

- make an image of a scheme by repeating each color m times in h rows

```
convert_to_scheme(cscheme, img)
```

- converts img from its current color values to use only the colors defined in cscheme.

```
compare_colors(color_a, color_b, field = :l)
```
- compare colors, return true if the specified field of `color_a` is less than `color_b`.

```
colorscheme_to_text(cs::Vector{C}, schemename::String, file::String; comment="") where {C <: Colorant}
```

- export colorscheme `schemename` to a text file

```
get(cscheme::Vector{C}, x) where {C <: Colorant}
```

- return a single color from `cscheme` based on `x` between 0 and 1

```
get(cscheme::Vector{C}, inData :: Array{Number, 2}, rangescale) where {C <: Colorant}
```

- return an RGB image (Array of colors) generated by applying the color scheme to `inData`. The mapping between values and ColorScheme can be adjusted with rangescale, see help on `get()`.

```
extract(imfile, n=10, i=10, tolerance=0.01; kwargs...)
```

- extract a new colorscheme from an image file, return a colorscheme

```
extract_weighted_colors(imfile, n=10, i=10, tolerance=0.01; shrink = 2.0)
```
- return a colorscheme and weights for each entry

```
image_to_swatch(imagefilepath, n::Int64, destinationpath; nrows=50, tilewidth=5)
```
- extract a colorscheme and save it as a swatch PNG in the destination file

```
schemes
```
- an array of names of all the available schemes, as symbols

```
sortcolorscheme(colorscheme::Vector{C}, field = :l; kwargs...) where {C <: Colorant}
```
- sort a colorscheme by `field` of the LUV colorspace

"""
module ColorSchemes

using Images, Colors, Clustering, FileIO, Dates

import Base.get

export
colorscheme_to_image,
colorscheme_to_text,
colorscheme_weighted,
extract,
extract_weighted_colors,
get,
getinverse,
convert_to_scheme,
image_to_swatch,
schemes,
sortcolorscheme,
@reg

"""
`schemes` contains the names of all the available colorschemes.
"""
const schemes = Symbol[]

"""
    reg(vname, args)

Load a variable and some values, and add the symbol to the list of schemes in
`schemes`.
"""
macro reg(vname, args)
    quote
        $(esc(push!(schemes, vname)))
        $(esc(vname)) = $(args)
    end
end

# load the installed schemes
include(dirname(@__FILE__) * "/../data/allcolorschemes.jl")
include(dirname(@__FILE__) * "/../data/colorbrewerschemes.jl")
include(dirname(@__FILE__) * "/../data/matplotlib.jl")
include(dirname(@__FILE__) * "/../data/cmocean.jl")

# the `schemes` array now contains the names of the built-in ColorSchemes

# convert a value between oldmin/oldmax to equivalent value between newmin/newmax

remap(value, oldmin, oldmax, newmin, newmax) =
    ((value .- oldmin) ./ (oldmax .- oldmin)) .* (newmax .- newmin) .+ newmin

"""
    extract(imfile, n=10, i=10, tolerance=0.01; shrink=n)

`extract()` extracts the most common colors from an image from the image file `imfile`
by finding `n` dominant colors, using `i` iterations. You can (and probably should)
shrink larger images before running this function.

Returns a colorscheme (an array of colors)
"""
function extract(imfile, n=10, i=10, tolerance=0.01; kwargs...)
    return extract_weighted_colors(imfile, n, i, tolerance; kwargs...)[1] # throw away the weights
end

"""
    extract_weighted_colors(imfile, n=10, i=10, tolerance=0.01; shrink = 2)

Extract colors and weights of the clusters of colors in an image file.

Example:

    pal, wts = extract_weighted_colors(imfile, n, i, tolerance; shrink = 2)
"""
function extract_weighted_colors(imfile, n=10, i=10, tolerance=0.01; shrink = 2.0)
    img = load(imfile)
    # TODO this is wrong, isn't it?
    (!@isdefined img) && error("Can't load the image file \"$imfile\"")
    w, h = size(img)
    neww = round(Int, w/shrink)
    newh = round(Int, h/shrink)
    smaller_image = Images.imresize(img, (neww, newh))
    w, h = size(smaller_image)
    imdata = convert(Array{Float64}, channelview(smaller_image))
    d = reshape(imdata, 3, :)
    R = kmeans(d, n, maxiter=i, tol=tolerance)
    colscheme = RGB{Float64}[]
    for i in 1:3:length(R.centers)
        push!(colscheme, RGB(R.centers[i], R.centers[i+1], R.centers[i+2]))
    end
    return colscheme, R.cweights/sum(R.cweights)
end

"""
    colorscheme_weighted(colorscheme, weights, length)

Returns a new colorscheme of length `length` (default 50) where the proportion
of each color in `colorscheme` is represented by the associated weight of each entry.

Examples:

```
colorscheme_weighted(extract_weighted_colors("hokusai.jpg")...)
colorscheme_weighted(extract_weighted_colors("filename00000001.jpg")..., 500)
```
"""
function colorscheme_weighted(cscheme::Vector{C}, weights, l = 50) where {C <: Colorant}
    iweights = map(n -> convert(Integer, round(n * l)), weights)
    #   adjust highest or lowest so that length of result is exact
    while sum(iweights) < l
        val, ix = findmin(iweights)
        iweights[ix]=val+1
    end
    while sum(iweights) > l
        val,ix = findmax(iweights)
        iweights[ix]=val-1
    end
    a = Array{RGB{Float64}}(undef, 0)
    for n in 1:length(cscheme)
        a = vcat(a, repeat([cscheme[n]], iweights[n]))
    end
    return a
end

"""
    compare_colors(color_a, color_b, field = :l)

Compare two colors, using the Luv colorspace. `field` defaults to luminance `:l`
but could be `:u` or `:v`. Return true if the specified field of `color_a` is
less than `color_b`.
"""
function compare_colors(color_a, color_b, field = :l)
    if 1 < color_a.r < 255
        fac = 255
    else
        fac = 1
    end
    luv1 = convert(Luv, RGB(color_a.r/fac, color_a.g/fac, color_a.b/fac))
    luv2 = convert(Luv, RGB(color_b.r/fac, color_b.g/fac, color_b.b/fac))
    return getfield(luv1, field) < getfield(luv2, field)
end

"""
    sortcolorscheme(colorscheme, field; kwargs...)

Sort (non-destructively) a colorscheme using a field of the LUV colorspace.

The less than function is `lt = (x,y) -> compare_colors(x, y, field)`.

The default is to sort by the luminance field `:l` but could be by `:u` or `:v`.
"""
function sortcolorscheme(colorscheme::Vector{C}, field = :l; kwargs...) where {C <: Colorant}
    sort(colorscheme, lt = (x,y) -> compare_colors(x, y, field); kwargs...)
end

"""

    get(cscheme, inData, rangescale)

<<<<<<< HEAD
Returns a single color.
"""
function get(cscheme::Vector{C}, x, rangescale) where {C<:Colorant}
    if rangescale==:clamp
        get(cscheme, x, (0.0, 1.0))
    elseif (rangescale==:extrema)
        get(cscheme, x, extrema(x))
    else
        error("rangescale ($rangescale) not supported, should be :clamp, :extrema or tuple (minVal, maxVal)")
    end
end

"""

    get(cscheme, inData :: Array{Number, 2}, rangescale=:clamp)
    get(cscheme, inData :: Array{Number, 2}, rangescale=(minVal, maxVal))

Return an RGB image (Array of colors) generated by applying the colorscheme to the 2D input data.

If `rangescale` is `:clamp` the colorscheme is applied to values between
0.0-1.0, and values outside this range get clamped to the ends of the
colorscheme.

Else, if `rangescale` is `:extrema`, the colorscheme is applied to the range
`minimum(indata)..maximum(indata)`.

# Examples

```
img = get(ColorSchemes.leonardo, rand(10,10))
save("testoutput.png", img)  # might need FileIO or similar

img2 = get(ColorSchemes.leonardo, 10.0*rand(10,10), :extrema)
img3 = get(ColorSchemes.leonardo, 10.0*rand(10,10), (1.0, 9.0))

# Also works with PerceptualColourMaps
using PerceptualColourMaps
img4 = get(PerceptualColourMaps.cmap("R1"), rand(10,10))
```
"""
function get(cscheme::Vector{<:Colorant},
             x::Union{<:Real, Array{<:Real}, AbstractRange{<:Real}},
             rangescale::Union{Symbol, NTuple{2, <:Real}}=(0.0, 1.0))

    # NOTE: the Union type for `x` is needed to avoid ambiguity with Base.get
    # when using ranges

    rangescale == :clamp   && (rangescale = (0.0, 1.0))
    rangescale == :extrema && (rangescale = extrema(x))
    (rangescale isa NTuple{2, Number}) || error("rangescale ($rangescale) not supported, should be :clamp, :extrema or tuple (minVal, maxVal)")
    x isa AbstractRange && (x = collect(x))
    x = clamp.(x, rangescale...)
    before_fp = remap(x, rangescale..., 1, length(cscheme))
    before = round.(Int, before_fp, RoundDown)
    after =  min.(before .+ 1, length(cscheme))
    # blend between the two colors adjacent to the point
    cpt = before_fp - before
    return weighted_color_mean.(1 .- cpt, cscheme[before], cscheme[after])
end

"""
    getinverse(cscheme, c, range=(0.0, 1.0))

Computes where the provided Color `c` would fit in `cscheme`.

This is the inverse of `get()` — it returns the value `x` in the provided `range`
for which `get(scheme, x)` would most closely match the provided Color `c`.

# Examples
```jldoctest
julia> getinverse(ColorSchemes.leonardo, RGB(1,0,0))
0.6248997995654847
julia> getinverse([Colors.RGB(0,0,0), Colors.RGB(1,1,1)], Colors.RGB(.5,.5,.5))
0.5432555858022048
julia> cs = range(Colors.RGB(0,0,0), stop=Colors.RGB(1,1,1), length=5)
julia> getinverse(cs, cs[3])
0.5
```
"""
function getinverse(cscheme::Vector{C}, c, rangescale :: Tuple{Number, Number}=(0.0, 1.0)) where {C<:Colorant}
    if length(cscheme) <= 1 ; throw(InexactError()) ; end
    cdiffs = map(c_i->colordiff(promote(c,c_i)...), cscheme)
    closest = argmin(cdiffs)
    left = right = 0;
    if closest == 1 ; left = closest; right = closest + 1;
    elseif closest == length(cscheme) ; left = closest - 1; right = closest;
    else
        next_closest = cdiffs[closest-1] < cdiffs[closest+1] ? closest-1 : closest+1
        left = min(closest, next_closest)
        right = max(closest, next_closest)
    end

    v = left
    if cdiffs[left] != cdiffs[right] ;  # Prevents divide by 0.
        v += ( cdiffs[left] / (cdiffs[left] + cdiffs[right]))
    end
    return ColorSchemes.remap(v, 1, length(cscheme), rangescale...)
end


"""
    convert_to_scheme(cscheme, img)

Converts img from its current color values to use only the colors defined in cscheme.

```
image = nonTransparentImg
convert_to_scheme(ColorSchemes.leonardo, image)
convert_to_scheme(ColorSchemes.Paired_12, image)
```
"""
convert_to_scheme(cscheme::Vector{C},img) where {C<:Colorant} =
    map(c->get(cscheme, getinverse(cscheme, c)), img)

"""
    colorscheme_to_text(cscheme, schemename, filename; comment="")

Write a colorscheme to a Julia file in a format suitable for `include`ing.

Example:

```
colorscheme_to_text(
    extract("/tmp/1920px-Great_Wave_off_Kanagawa2.jpg"),
        "hokusai_1",
        "/tmp/hok.jl",
        comment="from Hokusai's Great Wave")
```

To read a text file created thusly in and register it in `schemes`:

```
julia> include("/tmp/hok.jl")
julia> schemes[end]
:hokusai_1
julia> get(hokusai_1, .4)
RGB{Float64}(0.5787354153400166,0.49341844091747,0.22277034922842723)
```
"""
function colorscheme_to_text(cs::Vector{C}, schemename::String, file::String; comment="") where {C <: Colorant}
    fhandle = open(file, "w")
    write(fhandle, string("# ", comment, "\n"))
    write(fhandle, string("# created $(Dates.now())\n"))
    write(fhandle, string("@reg $schemename [\n", join(cs, ",\n"), " ]"))
    close(fhandle)
end

"""
    colorscheme_to_image(cs, nrows=50, tilewidth=5)

Make an image from a colorscheme by repeating the colors in a colorscheme.

Returns the image as an array.

Examples:

```
using FileIO

img = colorscheme_to_image(ColorSchemes.leonardo, 50, 200)
save("/tmp/cs_image.png", img)

save("/tmp/blackbody.png", colorscheme_to_image(ColorSchemes.blackbody, 10, 100))
```
"""
function colorscheme_to_image(cs::Vector{C}, nrows=50, tilewidth=5) where {C <: Colorant}
    ncols = tilewidth * length(cs)
    a = Array{RGB{Float64}}(undef, nrows, ncols)
    for row in 1:nrows
        for col in 1:ncols
            a[row, col] = cs[div(col-1, tilewidth) + 1]
        end
    end
    return a
end

"""
    image_to_swatch(imagefilepath, samples, destinationpath; nrows=50, tilewidth=5)

Extract a colorscheme from the image in `imagefilepath` to a swatch image PNG in
`destinationpath`. This just runs `sortcolorscheme()`, `colorscheme_to_image()`, and
`save()` in sequence.

Specify the number of colors. You can also specify the number of rows, and how many
times each color is repeated.

```
image_to_swatch("monalisa.jpg", 10, "/tmp/monalisaswatch.png")
```
"""
function image_to_swatch(imagefilepath, n::Int64, destinationpath; nrows=50, tilewidth=5)
    temp = sortcolorscheme(extract(imagefilepath, n))
    img = colorscheme_to_image(temp, nrows, tilewidth)
    save(destinationpath, img)
end

end
