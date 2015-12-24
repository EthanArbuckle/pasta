include theos/makefiles/common.mk

TWEAK_NAME = Pasta
Pasta_FRAMEWORKS = UIKit QuartzCore CoreGraphics
Pasta_FILES = Tweak.xm
Pasta_LIBRARIES = substrate
#Pasta_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 backboardd"
