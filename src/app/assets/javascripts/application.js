// This file maintained for backward compatibility.
// JavaScript has been split into multiple bundles for better performance:
//
// - core.js: Core libraries (jQuery, Bootstrap, utilities) - loaded on all pages
// - calendar_bundle.js: Calendar-specific code - loaded only on days#index
// - visits_bundle.js: Visits/trips management - loaded only on visits#index
//
// All bundles are loaded via application.html.erb layout conditionally.
// This file simply loads core.js to maintain compatibility with existing references.

//= require core
