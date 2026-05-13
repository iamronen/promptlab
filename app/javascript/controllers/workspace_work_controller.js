import { Controller } from "@hotwired/stimulus"

// Work area modes (v1: "panel" only). Reserved for future workspace modes.
export default class extends Controller {
  static values = {
    mode: String
  }
}
