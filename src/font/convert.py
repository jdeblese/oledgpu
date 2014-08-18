from PIL import Image
from math import log, ceil

log2 = lambda x : log(x) / log(2.0)

out = "meminit.vhd"
bmp = "bitmaps"
sep = "\\"
dl = 64

top = ""
bot = ""

for I in range(0, 255) :
	with Image.open(bmp + sep + "%2.2d.bmp"%I) as img :
		data = list(img.getdata())
		parsed = [0]*6
		for r in range(0, 8) :
			for c in range(0, 6) :
				if data[c + 6*r] != 0 :
					parsed[c] |= 2**(7-r)
		top += ''.join( map(lambda c: "%x"%(c>>4), parsed) ) + "00"
		bot += ''.join( map(lambda c: "%x"%(c&15), parsed) ) + "00"

top += ''.join( ['0'] * (dl - (len(top)%dl)) )
bot += ''.join( ['0'] * (dl - (len(bot)%dl)) )

prefix = '        INIT_%2.2X => X"'
suffix = '",'
fmt = lambda r : ''.join(reversed(r))

with open(out, "w") as fh :
	row = 0
	while len(bot) > 0 :
		fh.write(prefix%row + fmt(bot[:dl]) + suffix + "\n")
		bot = bot[dl:]
		row += 1
	row = 2**ceil(log2(row))
	while len(top) > 0 :
		fh.write(prefix%row + fmt(top[:dl]) + suffix + "\n")
		top = top[dl:]
		row += 1
