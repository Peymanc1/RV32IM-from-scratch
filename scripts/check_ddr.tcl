connect
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
puts "doom.bin @0x10000000 (expect non-zero instructions):"
mrd 0x10000000 4
puts "WAD magic @0x18000000 (expect 44415749 = 'IWAD'):"
mrd 0x18000000 4
