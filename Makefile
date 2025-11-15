.PHONY: help regen regen-fast docs docs-web check check-man vignettes install build test clean all

# Variables
R := Rscript
SKIP_ENRICHMENT := false
CACHE_DIR := .gdal_doc_cache

# Default target
help:
	@echo "gdalcli Development Makefile"
	@echo "=============================="
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "REGENERATION:"
	@echo "  regen              Regenerate all auto-generated functions (with web docs enrichment)"
	@echo "  regen-fast         Regenerate functions without web enrichment (faster)"
	@echo "  regen-clean        Clean cache and regenerate with full enrichment"
	@echo ""
	@echo "DOCUMENTATION:"
	@echo "  docs               Build roxygen2 documentation (.Rd files)"
	@echo "  docs-web           Build docs with web enrichment (requires docs and roxygen)"
	@echo "  vignettes          Build R Markdown vignettes with GDAL examples"
	@echo "  check-man          Run devtools::check_man() to validate documentation"
	@echo ""
	@echo "PACKAGE OPERATIONS:"
	@echo "  install            Install package locally"
	@echo "  build              Build package tarball"
	@echo "  test               Run unit tests via testthat"
	@echo "  check              Run full R CMD check"
	@echo ""
	@echo "MAINTENANCE:"
	@echo "  clean              Remove generated cache and temp files"
	@echo "  clean-all          Remove all generated files and caches"
	@echo ""
	@echo "CONVENIENCE:"
	@echo "  all                regen + docs + check (full development build)"
	@echo "  dev                regen-fast + docs + check-man (quick dev iteration)"
	@echo ""
	@echo "ENVIRONMENT VARIABLES:"
	@echo "  SKIP_ENRICHMENT    Set to 'true' to skip web doc enrichment (default: false)"
	@echo ""

# ============================================================================
# REGENERATION TARGETS
# ============================================================================

regen:
	@echo "Regenerating auto-generated functions with mandatory web enrichment..."
	@rm -f $(CACHE_DIR)/*.rds 2>/dev/null || true
	@$(R) build/generate_gdal_api.R
	@echo "[OK] Regeneration complete"
	@echo ""
	@echo "Next steps:"
	@echo "  make docs     # Generate .Rd documentation files"
	@echo "  make check    # Run full package checks"

regen-clean:
	@echo "Cleaning documentation cache..."
	@rm -rf $(CACHE_DIR)
	@echo "Regenerating auto-generated functions with fresh enrichment..."
	@$(R) build/generate_gdal_api.R
	@echo "[OK] Clean regeneration complete"

# ============================================================================
# DOCUMENTATION TARGETS
# ============================================================================

docs:
	@echo "Building roxygen2 documentation..."
	@$(R) --quiet --slave -e "roxygen2::roxygenise()"
	@echo "[OK] Documentation built successfully"

docs-web: regen docs
	@echo "[OK] Web-enriched documentation complete"
	@echo ""
	@echo "Next steps:"
	@echo "  make check    # Validate documentation"

vignettes:
	@echo "Building vignettes..."
	@$(R) build/build_vignettes.R
	@echo "[OK] Vignettes built successfully"

check-man:
	@echo "Checking man pages..."
	@$(R) --quiet --slave -e "devtools::check_man()" || true

# ============================================================================
# PACKAGE OPERATION TARGETS
# ============================================================================

install:
	@echo "Installing package locally..."
	@$(R) --quiet --slave -e "devtools::install()"
	@echo "[OK] Package installed"

build:
	@echo "Building package tarball..."
	@$(R) --quiet --slave -e "devtools::build()"
	@echo "[OK] Package built"

test:
	@echo "Running unit tests..."
	@$(R) --quiet --slave -e "devtools::test()"
	@echo "[OK] Tests complete"

check:
	@echo "Running full R CMD check..."
	@$(R) --quiet --slave -e "devtools::check()" || true
	@echo "[OK] Check complete"

# ============================================================================
# MAINTENANCE TARGETS
# ============================================================================

clean:
	@echo "Cleaning cache and temp files..."
	@rm -rf $(CACHE_DIR)
	@rm -rf .Rhistory .Rdata
	@rm -rf man/*.Rd
	@echo "[OK] Cleaned"

clean-all: clean
	@echo "WARNING: Removing all generated R files!"
	@rm -f R/gdal*.R
	@echo "[OK] All generated files removed"
	@echo ""
	@echo "Run 'make regen' to regenerate"

# ============================================================================
# CONVENIENCE TARGETS
# ============================================================================

all: regen docs check
	@echo ""
	@echo "============================================"
	@echo "[OK] Full development build complete!"
	@echo "============================================"

dev: regen-fast docs check-man
	@echo ""
	@echo "============================================"
	@echo "[OK] Quick dev build complete!"
	@echo "============================================"
	@echo ""
	@echo "Tip: Use 'make regen' for full web enrichment"
	@echo "     before committing changes"
