import sys
src, dst = sys.argv[1], sys.argv[2]
x = open(src, encoding='utf-8').read()
PROF = ('<profile name="" format="AUDIO_FORMAT_PCM_16_BIT" samplingRates="48000" '
        'channelMasks="AUDIO_CHANNEL_IN_MONO,AUDIO_CHANNEL_IN_STEREO"/>')

old_mix = '<mixPort name="usb_device input" role="sink"/>'
new_mix = '<mixPort name="usb_device input" role="sink">\n            ' + PROF + '\n        </mixPort>'
old_dev = '<devicePort tagName="USB Device In" type="AUDIO_DEVICE_IN_USB_DEVICE" role="source"/>'
new_dev = ('<devicePort tagName="USB Device In" type="AUDIO_DEVICE_IN_USB_DEVICE" role="source">\n            '
           + PROF + '\n        </devicePort>')
assert x.count(old_mix) == 1 and x.count(old_dev) == 1, 'unexpected source file'
x = x.replace(old_mix, new_mix).replace(old_dev, new_dev)
open(dst, 'w', encoding='utf-8', newline='\n').write(x)
print('ok, bytes:', len(x.encode('utf-8')))
