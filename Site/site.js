// The correction example in the hero, and the screen tabs on phones. No network, no storage.
(function () {
  "use strict";

  var $ = function (id) { return document.getElementById(id); };

  // Hero: tap the underline to see the rule, then show the fix.
  var mistake = $("mistake");
  if (mistake) {
    var fixed = $("fixed"), hint = $("hint"), card = $("issue-card"), corrected = $("corrected");
    var dot = $("dot"), count = $("count");

    var render = function (open, isFixed) {
      mistake.hidden = isFixed;
      fixed.hidden = !isFixed;
      hint.hidden = open || isFixed;
      card.hidden = !open || isFixed;
      corrected.hidden = !isFixed;
      mistake.setAttribute("aria-expanded", open ? "true" : "false");
      mistake.style.background = open ? "#fde3e1" : "transparent";
      dot.style.background = isFixed ? "#19805a" : "#e5322d";
      count.textContent = isFixed ? "All clear" : "1 to look at";
    };

    mistake.addEventListener("click", function () { render(true, false); });
    $("ignore").addEventListener("click", function () { render(false, false); mistake.focus(); });
    $("showfix").addEventListener("click", function () { render(false, true); $("reset").focus(); });
    $("reset").addEventListener("click", function () { render(false, false); mistake.focus(); });
    render(false, false);
  }

  // Phones: one app screen at a time.
  var tabs = document.querySelectorAll(".tab");
  var panels = document.querySelectorAll("[data-panel]");
  tabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      var chosen = tab.getAttribute("data-tab");
      tabs.forEach(function (t) { t.setAttribute("aria-pressed", t === tab ? "true" : "false"); });
      panels.forEach(function (p) { p.hidden = p.getAttribute("data-panel") !== chosen; });
    });
  });
})();
