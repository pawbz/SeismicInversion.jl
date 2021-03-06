"""
This module defines the following data types:
* `AGeom` : acquisition ageometry, i.e., positions of supersources, sources and receivers
* `Src` : source related acquisition parameters, e.g., source wavelet
It also provides methods that either does operations on these data type or 
help their construction.
"""
module Acquisition

import GeoPhyInv: Medium, χ
import GeoPhyInv.Utils
using Distributions
using DataFrames
using Random
using LinearAlgebra
using SparseArrays
using CSV
"""
Return some derived fields of `AGeom`

# Arguments 

* `acq::Vector{AGeom}` : a vector of `AGeom`
* `attrib::Symbol` : attribute to determine the return object 
  * `=:nus` number of unique source positions in acquisition
  * `=:nur` number of unique receiver positions in acquisition
  * `=:uspos` a tuple of x and z positions of all the unique sources
  * `=:urpos` a tuple of x and z position of all the unique receivers
  * `=:ageomurpos` a `AGeom` vector as if all the unique receiver positions are used for each supersource
  * `=:ageomuspos` a `AGeom` vector as if all the unique source positions are used for each supersource
"""
function AGeom_get(acq::Vector{AGeom}, attrib::Symbol)
	nageom = length(acq)
	sposx = AGeom_getvec(acq,:sx);	sposz = AGeom_getvec(acq,:sz)
	isequal(length(sposx), length(sposz)) ? 
		spos = [[sposz[is],sposx[is]] for is in 1:length(sposx)] : error("input acq corrupt")

	rposx = AGeom_getvec(acq,:rx);	rposz = AGeom_getvec(acq,:rz)
	isequal(length(rposx), length(rposz)) ? 
		rpos = [[rposz[ir],rposx[ir]] for ir in 1:length(rposx)] : error("input acq corrupt")

	uspos = unique(spos); nus=length(uspos)
	urpos = unique(rpos); nur=length(urpos)
	uspost = ([uspos[iu][1] for iu in 1:nus], [uspos[iu][2] for iu in 1:nus]);
        urpost = ([urpos[iu][1] for iu in 1:nur], [urpos[iu][2] for iu in 1:nur]);


	if(attrib == :nus)
		return nus
	elseif(attrib == :nur)
		return nur
	elseif(attrib == :uspos)
		return uspost
	elseif(attrib == :urpos)
		return urpost
	elseif(attrib == :ageomurpos)
		return [AGeom(acq[iageom].sx, acq[iageom].sz, 
	       fill(urpost[2],acq[iageom].nss), 
	       fill(urpost[1],acq[iageom].nss), acq[iageom].nss, acq[iageom].ns, 
	       fill(nur,acq[iageom].nss)) for iageom=1:nageom]
	elseif(attrib == :ageomuspos)
		return [AGeom(fill(uspost[2],acq[iageom].nss), 
	       fill(uspost[1],acq[iageom].nss),
	       acq[iageom].rx, acq[iageom].rz, 
	       acq[iageom].nss, fill(nus,acq[iageom].nss),
	       acq[iageom].nr) for iageom=1:nageom]
	else
		error("invalid attrib")
	end
end

"""
Given receiver positions `rpos` and `rpos0`.
Returns an array Int indices of the dimension of number of supersources
with `true` at indices, if the waves due to that particular source are 
recorded.
"""
function AGeom_find(acq::AGeom; rpos::Array{Float64,1}=nothing, rpos0::Array{Float64,1}=nothing)
	rpos==nothing ? error("need rpos") : nothing
	sson = Array{Vector{Int64}}(undef,acq.nss);
	for iss = 1:acq.nss
		rvec = [[acq.rz[iss][ir],acq.rx[iss][ir]] for ir=1:acq.nr[iss]]
		ir=findfirst(rvec, rpos)
		if(rpos0==nothing)
			ir0=1;
		else
			ir0=findfirst(rvec, rpos0);
		end
		sson[iss] = ((ir != 0) && (ir0 != 0)) ? [ir,ir0] : [0]
	end
	return sson
end

#=
"""
Modify input `AGeom` such that the output `AGeom` has
either sources or receivers on the boundary of 
`mgrid`.

# Arguments

* `ageom::AGeom` : input ageometry
* `mgridi` : grid to determine the boundary
* `attrib::Symbol` : decide return
  * `=:srcborder` sources on boundary (useful for back propagation)
  * `=:recborder` receivers on boundary
"""
function AGeom_boundary(ageom::AGeom,
	      mgrid
	      attrib::Symbol
	     )

	if((attrib == :recborder) | (attrib == :srcborder))
		bz, bx, nb = border(mgrid, 3, :inner)
	end
	"change the position of receivers to the boundary"
	if(attrib == :recborder)
		nr = nb; 		sx = ageom.sx;
		sz = ageom.sz;		ns = ageom.ns;
		nss = ageom.nss;
		return AGeom(sx, sz, fill(bx,nss), fill(bz,nss), nss, ns, fill(nr,nss))
	"change the position of source (not supersources) to the boundary for back propagation"
	elseif(attrib == :srcborder)
		ns = nb;		rx = ageom.rx;
		rz = ageom.rz;		nr = ageom.nr;
		nss = ageom.nss;
		return AGeom(fill(bx,nss), fill(bz,nss), rx, rz, nss, fill(ns,nss), nr)
	else
		error("invalid attrib")
	end
end
=#

"""
Check if the input acquisition ageometry is fixed spread.
"""
function AGeom_isfixed(ageom::AGeom)
	isfixed=false
	# can have different source positions, but also different number of sources? 
	for field in [:rx, :rz, :nr, :ns]
		f=getfield(ageom, field)
		if(all(f .== f[1:1]))
			isfixed=true
		else
			isfixed=false
			return isfixed
		end
	end
	return isfixed
end














"""
A fixed spread acquisition has same set of sources and 
receivers for each supersource.
This method constructs a 
fixed spread acquisition ageometry using either a
horizontal or vertical array of supersources/ receivers.
Current implementation has only one source for every supersource.

# Arguments 

* `ssmin::Float64` : minimum coordinate for sources
* `ssmax::Float64` : maximum coordinate for sources
* `ss0::Float64` : consant coordinate for sources
* `rmin::Float64` : minimum coordinate for receivers
* `rmax::Float64` : maximum coordinate for receivers
* `r0::Float64` : consant coordinate for receivers
* `nss::Int64` : number of supersources
* `nr::Int64` : number of receivers
* `ssattrib::Symbol=:horizontal` : supersource array kind
  `=:vertical` : vertical array of supersources
  `=:horizontal` horizontal array of supersources
* `rattrib::Symbol=:horizontal` : receiver array kind
  `=:vertical` : vertical array of receivers
  `=:horizontal` horizontal array of receivers
* `rand_flags::Vector{Bool}=[false, false]` : decide placement of supersources and receivers 
  `=[true, false]` : randomly place supersources for regularly spaced receivers
  `=[true, true]` : randomly place supersources and receivers
  `=[false, false]` : regularly spaced supersources and receivers
  `=[false, true]` : randomly place receivers for regularly spaced supersources 

# Return
* a fixed spread acquisition ageometry `AGeom`
"""
function AGeom_fixed(
	      ssmin::Real,
	      ssmax::Real,
	      ss0::Real,
	      rmin::Real,
	      rmax::Real,
	      r0::Real,
	      nss::Int64,
	      nr::Int64,
	      ssattrib::Symbol=:horizontal,
	      rattrib::Symbol=:horizontal,
 	      rand_flags::Vector{Bool}=[false, false];
	      ssα::Real=0.0,
	      rα::Real=0.0,
	      ns::Vector{Int64}=ones(Int,nss),
	      srad::Real=0.0
	     )

	ssmin=Float64(ssmin); rmin=Float64(rmin)
	ssmax=Float64(ssmax); rmax=Float64(rmax)
	ss0=Float64(ss0); r0=Float64(r0)
	ssα=Float64(ssα)*pi/180.
	rα=Float64(rα)*pi/180.


	ssarray = isequal(nss,1) ? fill(ssmin,1) : (rand_flags[1] ? 
					     Random.rand(Uniform(minimum([ssmin,ssmax]),maximum([ssmin,ssmax])),nss) : range(ssmin,stop=ssmax,length=nss))
	if(ssattrib==:horizontal)
		ssz = ss0.+(ssarray.-minimum(ssarray)).*sin(ssα)/cos(ssα); ssx=ssarray
	elseif(ssattrib==:vertical)
		ssx = ss0.+(ssarray.-minimum(ssarray)).*sin(ssα)/cos(ssα); ssz=ssarray
	else
		error("invalid ssattrib")
	end

	rarray = isequal(nr,1) ? fill(rmin,1) : (rand_flags[2] ? 
					  Random.rand(Uniform(minimum([rmin,rmax]),maximum([rmin,rmax])),nr) : range(rmin,stop=rmax,length=nr))
	if(rattrib==:horizontal)
		rz = r0.+(rarray.-minimum(rarray)).*sin(rα)/cos(rα); rx = rarray
	elseif(rattrib==:vertical)
		rx = r0.+(rarray.-minimum(rarray)).*sin(rα)/cos(rα); rz = rarray
	else
		error("invalid rattrib")
	end
	rxall = [rx for iss=1:nss];
	rzall = [rz for iss=1:nss];
	ssxall=[zeros(ns[iss]) for iss=1:nss];
	sszall=[zeros(ns[iss]) for iss=1:nss];
	for iss in 1:nss
		for is in 1:ns[iss]
			θ=Random.rand(Uniform(-Float64(pi),Float64(pi)))
			r = iszero(srad) ? 0.0 : Random.rand(Uniform(0,srad))
			x=r*cos(θ)
			z=r*sin(θ)
			ssxall[iss][is]=ssx[iss]+x
			sszall[iss][is]=ssz[iss]+z
		end
	end
	return AGeom(ssxall, sszall, rxall, rzall, nss, ns, fill(nr,nss))
end

"""
Circular acquisition. The sources and receivers can also be placed on a circle of radius
`rad`. The origin of the circle is at `loc`. 
This ageometry is unrealistic, but useful for testing.
Receivers are placed such that the limits 
of the angular offset are given by `θlim`

# Arguments

* `nss::Int64=10` : number of supersources
* `nr::Int64=10` : number receivers for each super source
* `loc::Vector{Float64}=[0.,0.]` : location of origin
* `rad::Vector{Float64}=[100.,100.]` : radius for source and receiver circles, for example,
  * `=[0.,100.]` for sources at the center of circle
* `θlim::Vector{Float64}=[0.,π]` : acquisition is limited to these angular offsets between 0 and π

# Return

* a circular acquisition ageometry `AGeom`
"""
function AGeom_circ(;
		   nss::Int64=10,
		   nr::Int64=10,
		   loc::Vector=[0.,0.],
		   rad::Vector=[100.,100.],
		   θlim::Vector=[0.,π]
	       )

	# modify nr such that approximately nr receivers are present in θlim
	nra = nr * convert(Int64, floor(π/(abs(diff(θlim)[1]))))

	(nra==0) && error("θlim should be from 0 to π")

	sxx, szz = circ_coord(loc..., nss, rad[1])
	rxxa, rzza = circ_coord(loc..., nra, rad[2])
	sx=Array{Array{Float64}}(undef,nss)
	sz=Array{Array{Float64}}(undef,nss)
	rx=Array{Array{Float64}}(undef,nss)
	rz=Array{Array{Float64}}(undef,nss)
	ns=Array{Int64}(undef,nss)
	nr=Array{Int64}(undef,nss)

	for iss=1:nss
		rangles = [angle(complex(rxxa[ira]-loc[2], rzza[ira]-loc[1])) for ira in 1:nra]
		sangles = angle(complex(sxx[iss]-loc[2], szz[iss]-loc[1]))
		diff = abs.(rangles.-sangles)
		diff = [min(diff[ira], (2π - diff[ira])) for ira in 1:nra]
		angles = findall(minimum(θlim) .<= diff .<= maximum(θlim))
		sx[iss] = [sxx[iss]]
		sz[iss] = [szz[iss]]
		ns[iss] = 1 
		nr[iss] = length(angles)
		rx[iss] = rxxa[angles]
		rz[iss] = rzza[angles]
	end
	ageom =  AGeom(sx, sz, rx, rz, nss, ns, nr)

	print(ageom, "circular acquisition ageometry")
	return ageom
end

function circ_coord(z, x, n, rad)
	θ = (n==1) ? [0.0] : collect(range(0, stop=2π, length=n+1))
	xx = (rad .* cos.(θ) .+ x)[1:n]
	zz = (rad .* sin.(θ) .+ z)[1:n]
	return xx, zz
end
	
end # module
