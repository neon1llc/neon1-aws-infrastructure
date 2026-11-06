# Bundled Terraform rules only, so lint needs no plugin downloads
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
