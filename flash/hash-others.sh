#!/system/bin/sh
S=/dev/block/by-name/super
echo 3 > /proc/sys/vm/drop_caches
echo "vendor  $(dd if=$S bs=4096 skip=229632 count=58414 2>/dev/null | sha256sum | cut -d' ' -f1)"
echo "product $(dd if=$S bs=4096 skip=288256 count=72608 2>/dev/null | sha256sum | cut -d' ' -f1)"
echo "odm     $(dd if=$S bs=4096 skip=360960 count=5051 2>/dev/null | sha256sum | cut -d' ' -f1)"
