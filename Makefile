include theos/makefiles/common.mk
export GO_EASY_ON_ME = 1
TWEAK_NAME = Pasta
Pasta_FRAMEWORKS = UIKit QuartzCore CoreGraphics CoreMedia CoreVideo CoreImage
Pasta_FILES = Tweak.xm
Pasta_LIBRARIES = substrate
#Pasta_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 backboardd"
