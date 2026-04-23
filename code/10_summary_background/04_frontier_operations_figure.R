#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(readr)
  library(scales)
  library(showtext)
})

source(file.path(Sys.getenv("REPLICATION_PACKAGE_ROOT", getwd()), "code", "shared", "paths.R"))

data_dir <- file.path(intermediate_data_dir, "frontier_operations")
output_dir <- file.path(summary_output_dir, "figures")
support_dir <- file.path(summary_output_dir, "support")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(support_dir, recursive = TRUE, showWarnings = FALSE)

calibri_regular <- "/Applications/Microsoft Word.app/Contents/Resources/DFonts/Calibri.ttf"
calibri_bold <- "/Applications/Microsoft Word.app/Contents/Resources/DFonts/Calibrib.ttf"
font_family <- "Helvetica"
if (file.exists(calibri_regular) && file.exists(calibri_bold)) {
  font_add("Calibri", regular = calibri_regular, bold = calibri_bold)
  font_family <- "Calibri"
}
showtext_auto()

asm_file <- file.path(data_dir, "Domestic Available Seat Miles .htm")
casm_file <- file.path(data_dir, "System Total Expense per Available Seat Mile (CASM ex fuel and Transport Related).htm")

if (!file.exists(asm_file) || !file.exists(casm_file)) {
  stop("Frontier operations support files are missing from ", data_dir)
}

extract_row_block <- function(lines, start_idx) {
  end_idx <- start_idx
  while (end_idx <= length(lines) && !grepl("</tr>", lines[end_idx], fixed = TRUE)) {
    end_idx <- end_idx + 1
  }
  paste(lines[start_idx:end_idx], collapse = " ")
}

extract_years <- function(file_path) {
  lines <- readLines(file_path, warn = FALSE, encoding = "latin1")
  start_idx <- grep(">1995<", lines, fixed = TRUE)[1]
  if (is.na(start_idx)) {
    stop("Could not find year header in ", file_path)
  }

  block <- extract_row_block(lines, start_idx)
  block_text <- gsub("<[^>]+>", " ", block)
  years <- regmatches(block_text, gregexpr("(19|20)[0-9]{2}", block_text, perl = TRUE))[[1]]
  years <- as.integer(years)

  if (length(years) == 0) {
    stop("Could not parse year values from ", file_path)
  }

  years
}

extract_series <- function(file_path, row_label) {
  lines <- readLines(file_path, warn = FALSE, encoding = "latin1")
  start_idx <- grep(paste0(">", row_label, "<"), lines, fixed = TRUE)[1]
  if (is.na(start_idx)) {
    stop("Could not find row ", row_label, " in ", file_path)
  }

  block <- extract_row_block(lines, start_idx)
  block_text <- gsub("<[^>]+>", " ", block)
  values <- regmatches(
    block_text,
    gregexpr("-?[0-9]+(?:,[0-9]{3})*(?:\\.[0-9]+)?", block_text, perl = TRUE)
  )[[1]]
  values <- as.numeric(gsub(",", "", values))

  if (length(values) == 0) {
    stop("Could not parse numeric values for ", row_label, " in ", file_path)
  }

  values
}

years <- extract_years(asm_file)
asm_values <- extract_series(asm_file, "Frontier")
casm_values <- extract_series(casm_file, "Frontier")
ulcc_sub_values <- extract_series(casm_file, "-- sub ULCC")

if (length(years) != length(asm_values) ||
    length(years) != length(casm_values) ||
    length(years) != length(ulcc_sub_values)) {
  stop("Parsed year and value lengths do not match across source files.")
}

frontier_ops <- tibble(
  year = years,
  asm_millions = asm_values,
  casm_ex_fuel_transport = casm_values,
  ulcc_sub_benchmark = ulcc_sub_values
) %>%
  filter(year >= 2010, year <= 2019) %>%
  mutate(
    asm_billions = asm_millions / 1000
  )

write_csv(frontier_ops, file.path(support_dir, "frontier_operations_series_2010_2019.csv"))

pivot_year <- 2014
ulcc_benchmark_2019 <- 6.0

base_theme <- theme_minimal(base_size = 16) +
  theme(
    text = element_text(family = font_family),
    plot.title = element_text(face = "bold", size = 15, hjust = 0.5, margin = margin(b = 6)),
    plot.subtitle = element_blank(),
    plot.caption = element_text(size = 10, color = "grey35", hjust = 0),
    axis.title.x = element_text(size = 11),
    axis.title.y = element_text(size = 11),
    axis.text = element_text(color = "black", size = 10),
    axis.line = element_line(color = "black", linewidth = 0.45),
    panel.border = element_blank(),
    panel.grid = element_blank(),
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA),
    plot.margin = margin(5.5, 5.5, 5.5, 5.5)
  )

asm_plot <- ggplot(frontier_ops, aes(x = year, y = asm_billions)) +
  annotate(
    "rect",
    xmin = pivot_year,
    xmax = Inf,
    ymin = -Inf,
    ymax = Inf,
    fill = "grey70",
    alpha = 0.18
  ) +
  geom_hline(yintercept = 0, color = "grey55", linewidth = 0.35) +
  geom_vline(xintercept = pivot_year, color = "grey60", linetype = "22", linewidth = 0.6) +
  geom_line(color = "grey20", linewidth = 0.9) +
  geom_point(color = "grey20", fill = "white", shape = 21, stroke = 0.8, size = 2.4) +
  scale_x_continuous(
    breaks = seq(2010, 2019, by = 1),
    expand = expansion(mult = c(0.02, 0.04))
  ) +
  scale_y_continuous(labels = label_number(accuracy = 0.1)) +
  labs(
    title = "Domestic Available Seat Miles",
    x = "Year",
    y = "Billions"
  ) +
  base_theme

casm_plot <- ggplot(frontier_ops, aes(x = year, y = casm_ex_fuel_transport)) +
  annotate(
    "rect",
    xmin = pivot_year,
    xmax = Inf,
    ymin = -Inf,
    ymax = Inf,
    fill = "grey70",
    alpha = 0.18
  ) +
  geom_hline(yintercept = ulcc_benchmark_2019, color = "grey45", linetype = "22", linewidth = 0.7) +
  annotate(
    "text",
    x = 2010.1,
    y = ulcc_benchmark_2019 + 0.12,
    label = paste0("ULCC benchmark: ", number(ulcc_benchmark_2019, accuracy = 0.1), "c"),
    hjust = 0,
    size = 4.2,
    color = "grey25"
  ) +
  geom_vline(xintercept = pivot_year, color = "grey60", linetype = "22", linewidth = 0.6) +
  geom_line(color = "grey20", linewidth = 0.9) +
  geom_point(color = "grey20", fill = "white", shape = 21, stroke = 0.8, size = 2.4) +
  scale_x_continuous(
    breaks = seq(2010, 2019, by = 1),
    expand = expansion(mult = c(0.02, 0.04))
  ) +
  scale_y_continuous(
    limits = c(4, 8),
    breaks = seq(4, 8, by = 1),
    labels = label_number(accuracy = 0.1)
  ) +
  labs(
    title = "Cost per Available Seat Mile Excluding Fuel",
    x = "Year",
    y = "Cents"
  ) +
  base_theme

pdf_out <- file.path(output_dir, "frontier_operations.pdf")
png_out <- file.path(output_dir, "frontier_operations.png")
legacy_pdf_out <- file.path(output_dir, "frontier_operations_poster_style.pdf")
legacy_png_out <- file.path(output_dir, "frontier_operations_poster_style.png")

render_combined_plot <- function(device_fun, filename, width, height, res = NULL) {
  if (is.null(res)) {
    device_fun(filename, width = width, height = height)
  } else {
    device_fun(filename, width = width, height = height, units = "in", res = res)
  }

  grid::grid.newpage()
  layout <- grid::grid.layout(nrow = 1, ncol = 2, widths = grid::unit(c(1, 1), "null"))
  grid::pushViewport(grid::viewport(layout = layout))
  print(asm_plot, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  print(casm_plot, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  grDevices::dev.off()
}

render_combined_plot(grDevices::pdf, pdf_out, width = 12, height = 5.6)
render_combined_plot(grDevices::png, png_out, width = 12, height = 5.6, res = 300)
file.copy(pdf_out, legacy_pdf_out, overwrite = TRUE)
file.copy(png_out, legacy_png_out, overwrite = TRUE)

message("Saved: ", pdf_out)
message("Saved: ", png_out)
message("Legacy aliases saved: ", legacy_pdf_out, " and ", legacy_png_out)
