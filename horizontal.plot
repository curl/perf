# SVG output
set terminal svg size 1920,380 dynamic font ",24" background rgb 'white'

# --- 1. Data Definitions ---
min_s = ARG1 + 0.0
p25_s = ARG2 + 0.0
med_s = ARG3 + 0.0
p75_s = ARG4 + 0.0
max_s = ARG5 + 0.0
avr_s = ARG6 + 0.0

unset xlabel
set format x "%.2s %c"

# Zoom X-axis to the data range (with padding) to prevent compression
set xrange [min_s - min_s/1000 : max_s + max_s/1000]

# Clean Y-axis layout
set yrange [0:2]
unset ytics
unset grid

# --- 3. Box & Whisker Geometry ---
y_pos = 1.0       # Central Y level
h_box = 0.65      # Box height
h_cap = 0.65      # Whisker cap half-height

# Central Box (P25 to P75)
set object 1 rectangle from p25_s, (y_pos - h_box) to p75_s, (y_pos + h_box) \
    fillcolor rgb "#2563EB" fillstyle solid 0.35 border lc rgb "#1E40AF" lw 4

# Whiskers (Min to P25, P75 to Max)
set arrow 1 from min_s, y_pos to p25_s, y_pos nohead lc rgb "#1E40AF" lw 4
set arrow 2 from p75_s, y_pos to max_s, y_pos nohead lc rgb "#1E40AF" lw 4

# Whisker Caps (Min and Max vertical bars)
set arrow 3 from min_s, (y_pos - h_cap) to min_s, (y_pos + h_cap) nohead lc rgb "#1E40AF" lw 4
set arrow 4 from max_s, (y_pos - h_cap) to max_s, (y_pos + h_cap) nohead lc rgb "#1E40AF" lw 4

# Median Line (Highlighted in Red)
set arrow 5 from med_s, (y_pos - h_box) to med_s, (y_pos + h_box) nohead lc rgb "#DC2626" lw 4

# Mean Line (Highlighted in Green)
set arrow 6 from avr_s, (y_pos - h_box) to avr_s, (y_pos + h_box) nohead lc rgb "#26AC26" lw 4

# --- 4. Point Annotations ---
set label 1 sprintf("P0") at min_s, (y_pos + h_cap + 0.18) center font ",18" tc rgb "#374151"
set label 2 sprintf("P25") at p25_s, (y_pos + h_box + 0.18) center font ",18" tc rgb "#374151"
set label 3 sprintf("Median") at med_s, (y_pos - h_box - 0.25) center font ",18" tc rgb "#DC2626"
set label 4 sprintf("P75") at p75_s, (y_pos + h_box + 0.18) center font ",18" tc rgb "#374151"
set label 5 sprintf("P100") at max_s, (y_pos + h_cap + 0.18) center font ",18" tc rgb "#374151"
set label 6 sprintf("Mean") at avr_s, (y_pos - h_box - 0.16) center font ",18" tc rgb "#26AC26"

# Render graphics canvas
plot NaN notitle
