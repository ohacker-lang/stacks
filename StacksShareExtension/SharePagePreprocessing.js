var ExtensionPreprocessingJS = {};

ExtensionPreprocessingJS.run = function (complete) {
  function meta(name) {
    var element = document.querySelector('meta[property="' + name + '"], meta[name="' + name + '"]');
    return element ? (element.getAttribute("content") || "").trim() : "";
  }

  function products(value) {
    if (!value || typeof value !== "object") return [];
    if (Array.isArray(value)) return value.reduce(function (all, child) { return all.concat(products(child)); }, []);
    var type = value["@type"];
    var found = type === "Product" || (Array.isArray(type) && type.indexOf("Product") !== -1) ? [value] : [];
    Object.keys(value).forEach(function (key) {
      if (key !== "@type") found = found.concat(products(value[key]));
    });
    return found;
  }

  function absoluteImage(value) {
    if (Array.isArray(value)) return absoluteImage(value[0]);
    if (value && typeof value === "object") return absoluteImage(value.url || value.contentUrl || value.src);
    if (typeof value !== "string") return "";
    try {
      var url = new URL(value, document.baseURI);
      return url.protocol === "https:" || url.protocol === "http:" ? url.href : "";
    } catch (_) { return ""; }
  }

  var candidates = [];
  var scripts = document.querySelectorAll('script[type="application/ld+json"]');
  for (var i = 0; i < scripts.length; i++) {
    try { candidates = candidates.concat(products(JSON.parse(scripts[i].textContent || ""))); } catch (_) {}
  }
  var path = location.pathname.replace(/\/$/, "");
  var product = candidates.find(function (entry) {
    try { return new URL(entry.url || entry["@id"] || "", location.href).pathname.replace(/\/$/, "") === path; }
    catch (_) { return false; }
  }) || candidates[0] || {};
  var brand = typeof product.brand === "string" ? product.brand : (product.brand && product.brand.name) || meta("product:brand");
  var offer = Array.isArray(product.offers) ? product.offers[0] : product.offers || {};
  var title = meta("og:title") || product.name || document.title || "";
  if (/^(?:product not found|page not found|404|access denied|attention required|just a moment)/i.test(title)) {
    complete({ url: location.href });
    return;
  }
  complete({
    url: location.href,
    title: String(title).slice(0, 180),
    brand: String(brand || "").slice(0, 80),
    imageURL: absoluteImage(product.image) || absoluteImage(meta("og:image")),
    price: String(offer.price || "").slice(0, 24),
    currencyCode: String(offer.priceCurrency || "").slice(0, 3)
  });
};
