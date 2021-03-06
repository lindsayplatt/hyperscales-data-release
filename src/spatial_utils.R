
fetch_zip_url_sf <- function(zip_url, layer_name){
  
  destination = tempfile(pattern = layer_name, fileext='.zip')
  file <- GET(zip_url, write_disk(destination, overwrite=T), progress())
  shp_path <- tempdir()
  unzip(destination, exdir = shp_path)

  sf::st_read(shp_path, layer=layer_name) %>%
    st_transform(crs = 4326) %>% 
    mutate(state = dataRetrieval::stateCdLookup(STATEFP)) %>% 
    dplyr::select(state, county = NAME)
  
}

sf_names_from_overlap <- function(sf_polys1, sf_polys2){
  
  # will be some NA when the point isn't contained within the polgyon:
  match_idx <- st_transform(sf_polys1, crs = "+init=epsg:2811") %>% sf::st_simplify(dTolerance = 40) %>% 
    st_transform(crs = st_crs(sf_polys2)) %>% 
    st_intersects(sf_polys2) 
  
  stopifnot(sum(sapply(match_idx, is.null)) == 0) # check that all poly1 have matches
  purrr::map(1:nrow(sf_polys1),function(i){
    info <- st_drop_geometry(sf_polys2[match_idx[[i]],])
    cbind(st_drop_geometry(sf_polys1[i,]), 
          lapply(info, function(x) { # lapply across the data.frame columns, squash/combine values when > 1
            paste(sort(unique(x)), collapse = '|')
            }) %>% data.frame(stringsAsFactors = FALSE))
  }) %>% purrr::reduce(bind_rows)
}

sf_to_zip <- function(zip_filename, sf_object, layer_name){
  cdir <- getwd()
  on.exit(setwd(cdir))
  dsn <- tempdir()
  
  sf::st_write(sf_object, dsn = dsn, layer = layer_name, driver="ESRI Shapefile", delete_dsn=TRUE) # overwrites
  
  files_to_zip <- data.frame(filepath = dir(dsn, full.names = TRUE), stringsAsFactors = FALSE) %>%
    mutate(filename = basename(filepath)) %>%
    filter(str_detect(string = filename, pattern = layer_name)) %>% pull(filename)
  
  setwd(dsn)
  zip(file.path(cdir, zip_filename), files = files_to_zip)
  setwd(cdir)
}

subset_lake_sf <- function(lakes_sf_fl, site_ids){
  readRDS(lakes_sf_fl) %>% filter(site_id %in% !!site_ids) %>% sf::st_zm()
}

plot_groups <- function(fileout, spatial_groups, county_bounds, lakes_sf_fl){
  png(filename = fileout, width = 8, height = 5.5, units = 'in', res = 500)
  par(omi = c(0,0,0,0), mai = c(0,0,0,0), xaxs = 'i', yaxs = 'i')
  
  n <- length(unique(spatial_groups$group_id))
  cols <- c('#a6cee3','#b2df8a','#1f78b4','#33a02c','#fb9a99','#e31a1c','#fdbf6f','#ff7f00','#cab2d6','#6a3d9a','#b15928',
            '#e41a1c','#377eb8','#984ea3','#a65628','#f781bf','#007f7f','#ff00ff')
  
  col_vector <- rep(cols, ceiling(n/length(cols)))[1:n]
  g_styles <- data.frame(group_id = unique(spatial_groups$group_id), col = col_vector, stringsAsFactors = FALSE)
  
  spatial_groups <- left_join(spatial_groups, g_styles, by = 'group_id')
  
  plot(st_geometry(spatial_groups), col = NA, border = NA, lwd = 0.1, reset = FALSE)
  all_lakes_simple <- readRDS(lakes_sf_fl) %>% st_transform(crs = "+init=epsg:2811") %>% sf::st_simplify(dTolerance = 40) %>% 
    st_transform(crs = "+init=epsg:4326")
  
  plot(st_geometry(all_lakes_simple), col = 'grey70', border = 'grey70', lwd = 0.1, add = TRUE)
  
  #plot(st_geometry(spatial_groups), col = paste0(spatial_groups$col, '4D'), border = 'grey70', lwd = 0.1, add = TRUE)
  
  county_bounds %>% st_geometry() %>% 
    plot(col = NA, border = 'grey80', lwd = 0.2, add = TRUE)
  
  county_bounds %>% group_by(state) %>% summarise() %>% st_geometry() %>% 
    plot(col = NA, border = 'grey40', lwd = 0.5, add = TRUE)
  
  invisible(list(sf = all_lakes_simple, style = g_styles))
}

plot_nccasc_lakes <- function(fileout, model_ids, county_bounds, lakes_sf_fl){
  
  dummy_geo <- county_bounds %>% filter(state %in% c('MN','ND','SD'))
  png(filename = fileout, width = 6.5, height = 5.5, units = 'in', res = 500)
  par(omi = c(0,0,0,0), mai = c(0,0,0,0), xaxs = 'i', yaxs = 'i')
  
  all_lakes_simple <- readRDS(lakes_sf_fl) %>% st_transform(crs = "+init=epsg:2811") %>% sf::st_simplify(dTolerance = 40) %>% 
    st_transform(crs = "+init=epsg:4326")
  
  plot(st_geometry(dummy_geo), col = NA, border = NA, lwd = 0.1, reset = FALSE)
  
  plot(st_geometry(all_lakes_simple), col = 'grey70', border = 'grey70', lwd = 0.1, add = TRUE)
  
  county_bounds %>% st_geometry() %>% 
    plot(col = NA, border = 'grey80', lwd = 0.2, add = TRUE)
  
  county_bounds %>% group_by(state) %>% summarise() %>% st_geometry() %>% 
    plot(col = NA, border = 'grey40', lwd = 0.5, add = TRUE)
  
  modeled_lakes_sf <- all_lakes_simple %>% filter(site_id %in% model_ids)
  plot(st_geometry(modeled_lakes_sf), col = 'dodgerblue', border = 'dodgerblue', lwd = 0.2, add = TRUE)
  
  dev.off()
  
}

plot_grouped_lakes_preview <- function(fileout, spatial_groups, county_bounds, site_ids_grouped, lakes_sf_fl){
  out <- plot_groups(fileout, spatial_groups, county_bounds, lakes_sf_fl)
  all_lakes_simple <- out$sf
  g_styles <- out$style
  

  modeled_lakes_sf <- inner_join(all_lakes_simple, site_ids_grouped, by = 'site_id') %>% 
    left_join(g_styles, by = 'group_id')
  
  plot(st_geometry(modeled_lakes_sf), col = 'dodgerblue', border = 'dodgerblue', lwd = 0.2, add = TRUE)
  
  # for (j in 1:nrow(spatial_groups)){
  #   bbox <- st_bbox(spatial_groups[j,])
  #   
  #   text(bbox[1], bbox[2]+0.1, str_extract(spatial_groups[j,]$group_id, '[0-9]{2}'), pos = 4, cex = 0.8, offset = 0.1)
  # }
  
  dev.off()
  
}

create_ldas_grid <- function(x0 = -124.9375, y0 = 25.0625, x_num = 464, y_num = 224, cell_res = 0.125){
  ldas_crs <- "+init=epsg:4326"
  
  ldas_grid_sfc <- sf::st_make_grid(cellsize = cell_res, n = c(x_num, y_num),
                                    offset = c(x0-cell_res/2, y0-cell_res/2), crs = ldas_crs)
  # cells count left to right, then next row, then left to right
  x_cells <- rep(0:(x_num-1), y_num)
  y_cells <- c(sapply(0:(y_num-1), function(x) rep(x, x_num)))
  
  ldas_grid <- st_sf(data.frame(x = x_cells, y = y_cells), ldas_grid_sfc)
  return(ldas_grid)
}


plot_grouped_cells_preview <- function(fileout, spatial_groups, county_bounds, site_ids_grouped, lakes_sf_fl, grouped_meteo_fls){
  

  meteos <- basename(grouped_meteo_fls$meteo_filepath)
  ldas_grid <- create_ldas_grid() %>% mutate(meteo_fl = sprintf('NLDAS_time[0.359420]_x[%s]_y[%s].csv', x, y)) %>% 
    filter(meteo_fl %in% meteos)
  
  
  plot_groups(fileout, spatial_groups, county_bounds, lakes_sf_fl)
  
  plot(st_geometry(ldas_grid), col = '#ff00ff33', border = '#ff00ffD3', lwd = 0.2, add = TRUE)
  
  for (j in 1:nrow(spatial_groups)){
    bbox <- st_bbox(spatial_groups[j,])
    
    text(bbox[1], bbox[2]+0.1, str_extract(spatial_groups[j,]$group_id, '[0-9]{2}'), pos = 4, cex = 0.8, offset = 0.1)
  }
  
  dev.off()
}