const scrollScene = document.getElementById("try-stacks");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

if (scrollScene && !reducedMotion.matches) {
  scrollScene.classList.add("motion-ready");
  const pieces = [...scrollScene.querySelectorAll(".assembly-product")];
  const restingRotations = [-8, 7, -7, 12, -8, 8];
  const mobileDepartureFactors = [
    [-0.46, -0.28, -22], [0.43, -0.34, 18], [-0.48, -0.03, -16],
    [0.46, 0.08, 20], [-0.42, 0.32, 14], [0.4, 0.4, -19],
  ];
  let queued = false;

  function render() {
    queued = false;
    const isMobile = window.innerWidth <= 700;
    const rect = scrollScene.getBoundingClientRect();
    const viewportHeight = Math.max(1, window.visualViewport?.height || window.innerHeight);
    const travel = Math.max(1, rect.height - viewportHeight);
    let progress;

    if (isMobile) {
      // Mobile Safari changes the visual viewport while its browser chrome
      // collapses. Anchor the scene to document scroll instead of rect.top so
      // the products keep moving smoothly through that resize.
      const sceneTop = window.scrollY + rect.top;
      const start = sceneTop - viewportHeight * 0.72;
      const mobileTravel = Math.max(viewportHeight * 1.05, Math.min(travel, viewportHeight * 1.5));
      progress = (window.scrollY - start) / mobileTravel;
    } else {
      progress = -rect.top / travel;
    }

    progress = Math.min(1, Math.max(0, progress));
    const easedMobileProgress = progress * progress * (3 - 2 * progress);
    const settled = isMobile ? easedMobileProgress : Math.min(1, progress / 0.9);
    const distanceScale = Math.min(1, Math.max(0.42, window.innerWidth / 1100));

    pieces.forEach((piece, index) => {
      const departure = 1 - settled;
      const [mobileXFactor, mobileYFactor, mobileAngle] = mobileDepartureFactors[index];
      const mobileX = window.innerWidth * mobileXFactor;
      const mobileY = viewportHeight * mobileYFactor;
      const x = (isMobile ? mobileX : Number(piece.dataset.fromX) * distanceScale) * departure;
      const y = (isMobile ? mobileY : Number(piece.dataset.fromY) * distanceScale) * departure;
      const angle = restingRotations[index] + (isMobile ? mobileAngle : Number(piece.dataset.fromRotation)) * departure;
      piece.style.transform = `translate3d(${x}px, ${y}px, 0) rotate(${angle}deg)`;
      piece.style.opacity = String(Math.min(1, 0.2 + settled * 1.25));
    });
    scrollScene.classList.toggle("assembled", settled >= 0.98);
  }

  function requestRender() {
    if (!queued) {
      queued = true;
      requestAnimationFrame(render);
    }
  }

  window.addEventListener("scroll", requestRender, { passive: true });
  window.addEventListener("resize", requestRender);
  window.visualViewport?.addEventListener("resize", requestRender);
  window.visualViewport?.addEventListener("scroll", requestRender, { passive: true });
  window.addEventListener("pageshow", requestRender);
  requestRender();
}

const demoProductImage = document.getElementById("demo-product-image");
if (demoProductImage) {
  const catalog = {
    "brown-script": ["LFDY Jacquard Beanie", "LFDY", "LFDY", "https://livefastdieyoung.com/en-us/products/lfdy-jacquard-beanie-13", "$25.00", "USD · price checked September 23, 2026."],
    "green-stripe": ["Striped beanie", "Top Headwear", "Amazon", "https://www.amazon.com/dp/B076147M54", "Check Amazon", "A current price could not be verified for this listing.", "View on Amazon"],
    "rust-vintage": ["Reclaimed Vintage beanie", "Reclaimed Vintage", "ASOS", "https://www.asos.com/de/reclaimed-vintage/reclaimed-vintage-unisex-skull-cap-strickmutze-in-rostrot-mit-logo/prd/208475824", "€17.99", "EUR · listed price checked September 23, 2026; availability varies by region."],
    "blue-logo": ["Stüssy skullcap", "Stüssy", "AFewVibe", "https://sovrn.co/1k95w96", "$88.00", "USD · price checked September 23, 2026."],
    "burgundy-bird": ["Arc’teryx Grotto Toque", "Arc’teryx", "Arc’teryx", "https://arcteryx.com/us/en/shop/grotto-toque-0980?colour=17704", "$60.00", "USD · price checked September 23, 2026."],
    "coral-wave": ["Blue Tomato Y2K Beanie", "Blue Tomato", "MyBestBrands", "https://www.mybestbrands.de/marken/blue-tomato/accessoires/252.a0a5532f1c90c75168bdd99e9aca1a0e", "€24.95", "EUR · listed price; sold out at this source.", "View at MyBestBrands"],
    "black-columbia": ["Columbia Heat II Beanie", "Columbia", "Columbia", "https://www.columbia.com/p/columbia-heat-ii-beanie-2053191.html", "Out of stock", "Columbia does not currently publish a price for this item.", "View at Columbia"],
    "slate-bird": ["Arc’teryx Bird Head Toque", "Arc’teryx", "StockX", "https://stockx.com/arcteryx-bird-head-toque-nightscape-glacial", "From $85", "USD · marketplace ask checked September 23, 2026; fees and price vary."],
    "lilac-mountain": ["Blue Bison Mountain Peaks Beanie", "Blue Bison", "Blue Bison", "https://www.bluebisonapparel.com/products/mountain-peaks-skull-cap-beanie-purple", "$30.00", "USD · price checked September 23, 2026."],
    "bird-head-yellow": ["Arc’teryx Bird Head Toque", "Arc’teryx", "Arc’teryx", "https://arcteryx.com/us/en/shop/bird-head-toque", "$60.00", "USD · price checked September 23, 2026."],
    "blue-flame": ["Blue Flame Skull Cap Beanie", "Blue Bison", "Blue Bison", "https://www.bluebisonapparel.com/products/blue-flame-skull-cap-beanie", "$30.00", "USD · price checked September 23, 2026."],
    "orange-peaks": ["Mountain Peaks Skull Cap Beanie", "Blue Bison", "Blue Bison", "https://www.bluebisonapparel.com/products/mountain-peaks-skull-cap-beanie-orange", "$30.00", "USD · price checked September 23, 2026."],
  };
  const slug = window.location.pathname.split("/").filter(Boolean).at(-1);
  const product = catalog[slug];
  if (product) {
    const [name, brand, merchant, productURL, price, , actionLabel] = product;
    demoProductImage.src = `/assets/beanie-${slug}.webp`;
    demoProductImage.alt = name;
    document.getElementById("demo-product-title").textContent = name;
    document.getElementById("demo-product-brand").textContent = brand;
    document.getElementById("demo-product-price").textContent = price;
    const productLink = document.getElementById("demo-product-link");
    productLink.href = productURL;
    productLink.querySelector("span").textContent = actionLabel ?? `Buy from ${merchant}`;
    if (slug === "blue-logo") {
      const disclosure = document.getElementById("demo-product-disclosure");
      disclosure.textContent = "Affiliate link: Stacks may earn a commission if you buy through this link.";
      disclosure.hidden = false;
    }
    document.title = `${name} · Stacks`;
  }
}

const demoShareButton = document.querySelector(".demo-share-action");
if (demoShareButton) {
  demoShareButton.addEventListener("click", async () => {
    const url = new URL("/demo/beanies", window.location.origin).href;
    try {
      if (navigator.share) {
        await navigator.share({ title: "Beanies by Aliva Yakatori · Stacks", url });
      } else {
        await navigator.clipboard.writeText(url);
        document.getElementById("demo-share-status").textContent = "Beanies link copied";
      }
    } catch (error) {
      if (error.name !== "AbortError") document.getElementById("demo-share-status").textContent = "Could not share this Stack";
    }
  });
}
