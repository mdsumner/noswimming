
midpt <- function(p,fold=FALSE) {
  ## SWotherspoon/SGAT::trackMidpts
  wrapLon <- function(lon,lmin=-180)
    (lon-lmin)%%360+lmin
  n <- nrow(p)
  rad <- pi/180
  p <- rad*p
  dlon <- diff(p[,1L])
  lon1 <- p[-n,1L]
  lat1 <- p[-n,2L]
  lat2 <- p[-1L,2L]
  bx <- cos(lat2)*cos(dlon)
  by <- cos(lat2)*sin(dlon)
  lat <- atan2(sin(lat1)+sin(lat2),sqrt((cos(lat1)+bx)^2+by^2))/rad
  lon <- (lon1+atan2(by,cos(lat1)+bx))/rad
  if(fold) lon <- wrapLon(lon)
  cbind(lon,lat)
}
laea <- function(x) {
  pt <- as.integer(round(midpt(x)))
  sprintf("+proj=laea +lon_0=%i +lat_0=%i", pt[1], pt[2])
}

#' Make a global topography in a projection, with input longlat points in the centre
#'
#' Input is two longlat points
#'
#'
#' CRS is Lambert Azimuthal Equal Area, determined around the centre of the input points.
#'
#' @param x  matrix of 2 points, lon,lat
#' @param ncols number of columns of the output (default is 1024, which is about 26km resolution for the globe)
#' @param nrows ditto ncols (default is ncols)
#'
#' @return raster of global topography
#' @export
#'
#' @examples
#' make_global_topo(cbind(c(-90, 90), c(-70, -60)))
make_global_topo <- function(x, ncols = 1024, nrows = ncols) {
  dsn <- "/vsicurl/https://gebco2023.s3.valeria.science/gebco_2023_land_cog.tif"
  r <- terra::rast(dsn)
  proj <- laea(x)
  pts <- terra::project(x, to = proj, from = "EPSG:4326")
  terra::project(r, terra::rast(terra::ext(-1, 1, -1, 1) * 6378137 * pi/1.5, ncols = ncols, nrows = nrows, crs = proj), by_util = TRUE)
}

#' Make surface for cost surface creation
#'
#' This sets a DEM to have NA values for anywhere out of bounds, with a fill value of 1
#' everywhere else.
#'
#' If this isn't a good input to create_cs create a suitable one, perhaps starting with make_global_topo().
#'
#' Note that fill must be positive value else it seems to fail with leastcostpath.
#'
#' @param x a raster, can have missing values
#' @param maxvalue maximum value for the reachable areas (default to 0)
#' @param minvalue minimum value for the reachable areas (default to -Inf)
#' @param fillvalue 1 (should be positive)
#'
#' @return a raster
#' @export
#'
#' @examples
#' make_na_surface(terra::rast(volcano), maxvalue = 130)
make_na_surface <- function(x, maxvalue = 0, minvalue = -Inf, fillvalue = 1) {
  p <- terra::deepcopy(x)
  p[p > maxvalue] <- NA
  p[p < minvalue] <- NA
  p[!is.na(p)] <- fillvalue
  p
}


#' Create least cost path between two points
#'
#' By default we assuming swimming in the ocean, swimming on land is not allowed.
#'
#' @param x x  matrix of 2 points, lon,lat
#' @param surf surface for use by create_cs
#'
#' @return terra vect path
#' @export
#'
#' @examples
#' lcp(cbind(c(-90, 90), c(-70, -60)))
lcp <- function(x, surf = NULL) {
  if (is.null(surf)) {
    topo <- make_global_topo(x)
    surf <- make_na_surface(topo)
  }
  cost <- leastcostpath::create_cs(surf)
  vpt <- terra::project(terra::vect(x, crs = "EPSG:4326"), terra::crs(topo))
  ## all values should be valid (else it won't work)
  v <- terra::extract(surf, vpt, ID = FALSE)[,1L]
  if (anyNA(v)) stop("points on areas not valid for the cost surface")
  ## note this is sensible for the projected grid
  leastcostpath::create_lcp(cost, vpt[1, ], vpt[2, ])
}



