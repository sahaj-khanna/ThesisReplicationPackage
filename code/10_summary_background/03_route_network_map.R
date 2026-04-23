### econ 495 panel view and network map file
# last updated: 12 February, 2026

################################################################################
#                          SECTION 1: SETUP                                    #
################################################################################

### system instructions
rm(list = ls())
options(scipen = 999)

source(file.path(Sys.getenv("REPLICATION_PACKAGE_ROOT", getwd()), "code", "shared", "paths.R"))

input <- input_final_dir
figures_dir <- file.path(summary_output_dir, "figures")
dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)

### install packages if needed
# install.packages(c("maps", "airportr", "showtext"))

### loading packages
library(data.table)
library(tidyverse)
library(zoo)
library(fst)
library(panelView)
library(showtext)

### register Calibri from Office font bundle (fallback to Helvetica if unavailable)
calibri_regular <- "/Applications/Microsoft Word.app/Contents/Resources/DFonts/Calibri.ttf"
calibri_bold <- "/Applications/Microsoft Word.app/Contents/Resources/DFonts/Calibrib.ttf"
font_family <- "Helvetica"
if (file.exists(calibri_regular) && file.exists(calibri_bold)) {
  font_add("Calibri", regular = calibri_regular, bold = calibri_bold)
  font_family <- "Calibri"
}
showtext_auto()

################################################################################
#                   SECTION 2: LOAD DATASET                                    #
################################################################################

panel_data <- as.data.table(
  read_fst(file.path(input, "final_dataset_unfiltered.fst"))
)

################################################################################
#                   SECTION 3: PANEL VIEW — TREATMENT TIMING                   #
################################################################################

# Collapse to route-level panel (one row per route-quarter)
route_panel <- panel_data[, .(
  first_treat = first_treat[1],
  route_type  = route_type[1],
  origin      = origin[1],
  dest        = dest[1],
  mean_fare   = mean(average_fare, na.rm = TRUE)
), by = .(route, time_period)]

# Binary treatment indicator: 1 if route is treated AND current period >= entry
route_panel[, D := as.integer(first_treat > 0 & time_period >= first_treat)]

# Keep only treated and never-treated (drop pre-existing F9 routes)
route_panel_clean <- route_panel[route_type != "F9 Pre-Existing"]

# Panel view: treatment timing plot
panelview(mean_fare ~ D,
          data  = as.data.frame(route_panel_clean),
          index = c("route", "time_period"),
          type  = "treat",
          by.timing = TRUE,
          main  = "Treatment Status by Route Entry Cohort",
          xlab  = "Time Period (1 = 2011 Q1)",
          ylab  = "Routes (grouped by entry cohort)")

################################################################################
#                   SECTION 4: NETWORK MAP — FRONTIER ROUTE EXPANSION          #
################################################################################

library(maps)
library(airportr)
library(patchwork)

# --- 4a. Get unique routes by type ---
f9_routes <- panel_data[route_type == "F9 Entry (Post-Shift)",
                        .(origin = origin[1], dest = dest[1], first_treat = first_treat[1]),
                        by = route]
# Canonicalize direction: treat A→B same as B→A
f9_routes[, c("origin", "dest") := .(pmin(origin, dest), pmax(origin, dest))]
f9_routes <- unique(f9_routes, by = c("origin", "dest"))
f9_routes[, type := "Post-Transition Entry"]

pre_routes <- panel_data[route_type == "F9 Pre-Existing",
                         .(origin = origin[1], dest = dest[1]),
                         by = route]
# Canonicalize direction: treat A→B same as B→A
pre_routes[, c("origin", "dest") := .(pmin(origin, dest), pmax(origin, dest))]
pre_routes <- unique(pre_routes, by = c("origin", "dest"))
pre_routes[, type := "Pre-Existing Route"]

all_f9_routes <- rbind(f9_routes, pre_routes, fill = TRUE)

# --- 4b. Get airport coordinates ---
all_airports <- unique(c(all_f9_routes$origin, all_f9_routes$dest))

# Use airportr's built-in airports dataset directly
apt_data <- as.data.table(airportr::airports)
coords <- apt_data[IATA %in% all_airports, .(iata = IATA, lat = Latitude, lon = Longitude)]
coords <- coords[!is.na(lat) & !is.na(lon)]

# Merge coordinates onto routes
routes_geo <- merge(all_f9_routes, coords, by.x = "origin", by.y = "iata", all.x = FALSE)
setnames(routes_geo, c("lat", "lon"), c("origin_lat", "origin_lon"))
routes_geo <- merge(routes_geo, coords, by.x = "dest", by.y = "iata", all.x = FALSE)
setnames(routes_geo, c("lat", "lon"), c("dest_lat", "dest_lon"))

# --- 4c. Plot network map ---
us_map <- map_data("state")

# Set factor levels so pre-existing draws first, new entries on top
routes_geo[, type := factor(type, levels = c("Pre-Existing Route", "Post-Transition Entry"))]

# TOGGLE: "combined" = both on one map, "facet" = side-by-side panels
map_mode <- "facet"

# Base map layer (reused in both modes)
base_map <- ggplot() +
  geom_polygon(data = us_map,
               aes(x = long, y = lat, group = group),
               fill = "grey99", color = "black", linewidth = 0.2) +
  theme_minimal() +
  theme(
    text = element_text(family = font_family),
    legend.position = "bottom",
    axis.text  = element_blank(),
    axis.title = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

if (map_mode == "combined") {

  p <- base_map +
    geom_curve(data = routes_geo[order(type)],
               aes(x = origin_lon, y = origin_lat,
                   xend = dest_lon, yend = dest_lat,
                   color = type),
               curvature = 0.2, alpha = 0.1, linewidth = 0.35) +
    scale_color_manual(name = NULL,
                       values = c("Pre-Existing Route"    = "#1463F3",
                                  "Post-Transition Entry" = "firebrick"),
                       drop = FALSE) +
    geom_point(data = coords[iata %in% all_f9_routes$origin | iata %in% all_f9_routes$dest],
               aes(x = lon, y = lat),
               color = "grey30", size = 0.5) +
    coord_fixed(ratio = 1.3, xlim = c(-125, -67), ylim = c(24, 50)) +
    labs(title = "Frontier Airlines Route Network: Pre-Existing vs. Post-Transition Entry",
         subtitle = "Routes prior to ULCC model vs. routes entered after ULCC model") +
    theme(
      plot.title = element_text(family = font_family, size = 20, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 14, hjust = 0.5)
    )

  ggsave(file.path(figures_dir, "frontier_route_network.pdf"), plot = p,
         width = 10, height = 6.5, dpi = 300)

} else if (map_mode == "facet") {

  # Split routes for different color treatments
  pre_geo  <- routes_geo[type == "Pre-Existing Route"]
  post_geo <- routes_geo[type == "Post-Transition Entry"]
  # Randomly keep 75% of post-entry routes to reduce right-panel visual density.
  set.seed(495)
  if (nrow(post_geo) > 0) {
    keep_n <- max(1L, floor(0.75 * nrow(post_geo)))
    post_geo <- post_geo[sample(.N, keep_n)]
  }
  coords_map <- coords[iata %in% all_f9_routes$origin | iata %in% all_f9_routes$dest]

  pre_plot <- base_map +
    geom_curve(data = pre_geo,
               aes(x = origin_lon, y = origin_lat,
                   xend = dest_lon, yend = dest_lat),
               color = "#0F6744", curvature = 0.2, alpha = 1, linewidth = 0.4) +
    geom_point(data = coords_map,
               aes(x = lon, y = lat),
               color = "grey40", size = 0.6) +
    coord_cartesian(xlim = c(-125, -67), ylim = c(24, 50)) +
    labs(title = "Pre-ULCC Pivot Network (Before 2014)") +
    theme(
      aspect.ratio    = 0.62,
      legend.position = "none",
      plot.title = element_text(family = font_family, size = 15, face = "bold", hjust = 0.5),
      plot.margin = margin(t = 5.5, r = 0, b = 0, l = 5.5)
    )

  post_plot <- base_map +
    geom_curve(data = post_geo,
               aes(x = origin_lon, y = origin_lat,
                   xend = dest_lon, yend = dest_lat,
                   color = first_treat),
               curvature = 0.2, alpha = 0.75, linewidth = 0.4) +
    geom_point(data = coords_map,
               aes(x = lon, y = lat),
               color = "grey30", size = 0.6) +
    scale_color_gradientn(
      name = "Entry Year",
      colours = c("#DCECE6", "#0F6744", "#111111"),
      values = c(0, 0.5, 1),
      breaks = c(13, 17, 21, 25, 29, 33),
      labels = c("2014", "2015", "2016", "2017", "2018", "2019"),
      guide = guide_colorbar(
        title.position = "left",
        title.hjust = 0.5,
        label.position = "bottom",
        ticks = FALSE,
        barwidth = unit(6.4, "cm"),
        barheight = unit(0.5, "cm")
      )
    ) +
    coord_cartesian(xlim = c(-125, -67), ylim = c(24, 50)) +
    labs(title = "Post-ULCC Pivot Entries (2014\u20132019)") +
    theme(aspect.ratio     = 0.62,
          legend.position  = "bottom",
          plot.title = element_text(family = font_family, size = 15, face = "bold", hjust = 0.5),
          legend.title = element_text(family = font_family, size = 12, vjust = 0.5),
          legend.text = element_text(family = font_family, size = 11, hjust = 0.5),
          legend.direction = "horizontal",
          legend.margin = margin(t = -5, r = 0, b = -3, l = 0),
          legend.box.margin = margin(t = -7, r = 0, b = -4, l = 0),
          plot.margin = margin(t = 5.5, r = 5.5, b = 0, l = 0))

  p <- pre_plot + post_plot +
    plot_layout(ncol = 2)

  ggsave(file.path(figures_dir, "frontier_route_network_facet.pdf"), plot = p,
         width = 12, height = 5.6, dpi = 300)
  ggsave(file.path(figures_dir, "frontier_route_network_facet_highres.png"), plot = p,
         width = 16, height = 7.5, dpi = 600, bg = "white")
}

print(p)
