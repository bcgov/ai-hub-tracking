locals {
  # Normalize location for resource naming (e.g., "Canada Central" -> "canada-central")
  location_slug = replace(lower(var.location), "/[^0-9a-z-]/", "-")
}
