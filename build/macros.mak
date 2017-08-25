# Macros and functions to share across makefiles

# These macros make it prettier to call R by leveraging a known project structure.
# Try calling the examples, e.g., as `make -f macros.mak eg_dirvars`

all : eg_dirvars eg_rscript eg_addlog
	rm eg_addlog.Rlog
	@echo "--- finished running all examples in macros.mak ---"

## EXAMPLES ##

# These macros separate the target's dependencies into categories by dir & extension
# (the $@ target comes with make; see https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html)
eg_dirvars : 1_get_raw_data/src/get_siteinfo.R 1_get_raw_data/cfg/sample_config.yaml 1_get_raw_data/out/README.md
	@echo '--- eg_dirvars ---'
	@echo 'target: "$@"'
	@echo 'SRC: ${SRC}'
	@echo 'RSC: ${RSC}'
	@echo 'LIB: ${LIB}'
	@echo 'RLB: ${RLB}'
	@echo 'CFG: ${CFG}'
	@echo 'OUT: ${OUT}'

# A low-text way to call Rscript and load R script dependencies all at once
eg_rscript : 1_get_raw_data/src/*.R
	@echo '--- eg_rscript ---'
	${RSCRIPT} -e '1+2'

# Redirects all output, messages, and errors to a single .Rlog file named after the target
# (you may want to call `rm eg_addlog.Rlog` after calling `make -f macros.mak eg_addlog`)
eg_addlog : 1_get_raw_data/src/*.R
	@echo '--- eg_addlog ---'
	${RSCRIPT} -e 'print(1+2); message ("hi"); warning("oops")' ${ADDLOG}


## DEFINITIONS ##

# rvector turns space-separated list of unquoted strings 
# into comma-separated list of quoted strings wrapped in c()
dquote := "
comma := ,
null :=
space := $(null) $(null)
vecpre := c(
vecpost := )
define rvector
$(addprefix $(vecpre),$(addsuffix $(vecpost),$(subst $(space),$(comma),$(addprefix $(dquote),$(addsuffix $(dquote),$(strip $(1)))))))
endef

# Helpers that create R-friendly vectors of filenames selected from
# the dependencies listed for the current target
CFG=$(call rvector,$(filter $(wildcard */cfg/*.*),$^))
SRC=$(call rvector,$(filter $(wildcard */src/*.*),$^))
RSC=$(call rvector,$(filter $(wildcard */src/*.R),$^))
LIB=$(call rvector,$(filter $(wildcard lib/*.*),$^))
RLB=$(call rvector,$(filter $(wildcard lib/*.R),$^))
OUT=$(call rvector,$(filter $(wildcard */out/*.*),$^))
RSL=$(call rvector,$(filter $(wildcard lib/*.R),$^) $(filter $(wildcard */src/*.R),$^))

# Call R via ${RSCRIPT} to avoid typing all this. Automatically loads
# any dependencies in the /src/ directory and ending in R
RSCRIPT=Rscript -e 'x <- lapply(${RSL}, source)'

# ${ADDLOG} at the end of an Rscript call directs both stdout and stderr
# to a file named like the target but with the .Rlog suffix
LOGFILE=$(subst src/,,$(dir $(word 1,$(filter $(wildcard */src/*.*),$^))))log/$(notdir $(basename $@)).Rlog
ADDLOG=-e 'warnings()' -e 'devtools::session_info()' > ${LOGFILE} 2>&1

# this macro creates a timestamp text string in UTC
DATETIME=echo "$(shell date -u '+%Y-%m-%d %H:%M:%S %z')"

# for attaching to the end of an RSCRIPT expression. posts the data file to S3, creates an .s3 status indictor file, and updates the data file's timestamp so make understands that it's up to date relative to the status file.
POSTS3=-e 'post_s3(file.name="$(subst .s3,,$@)", s3.config="lib/s3_config.yaml")'\
		${ADDLOG};\
	${DATETIME} > $@;\
	touch $(subst .s3,,$@)

# this rule automatically looks to s3 if an *.s3 file exists and the corresponding * file is required. important for a shared cache.
% : %.s3\
		lib/s3.R lib/s3_config.yaml
	${RSCRIPT}\
		-e 'get_s3(file.name="$@", s3.config="lib/s3_config.yaml")'\
		-e 'warnings()' -e 'devtools::session_info()' > $(dir $(patsubst %/,%,$(dir $@)))log/$(notdir $(basename $@)).s3log 2>&1
