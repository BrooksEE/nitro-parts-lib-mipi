NITRO_PARTS_DIR ?= ../..

MIPI_DIR = $(NITRO_PARTS_DIR)/lib/mipi

INC_PATHS +=\
	$(MIPI_DIR)/rtl \

SIM_FILES += \
	$(MIPI_DIR)/rtl/mipi_csi2_ser.v \
	$(MIPI_DIR)/rtl/mipi_phy_ser.v \
	$(NITRO_PARTS_DIR)/lib/VerilogTools/sim/PLL_sim.v \
	$(NITRO_PARTS_DIR)/lib/VerilogTools/rtl/fifo.v \

SYN_FILES += \
	$(MIPI_DIR)/rtl/mipi_csi2_des.v \
	$(MIPI_DIR)/rtl/mipi_phy_des.v \

