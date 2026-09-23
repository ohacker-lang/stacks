const scrollScene = document.getElementById("try-stacks");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

if (scrollScene && !reducedMotion.matches) {
  scrollScene.classList.add("motion-ready");
  const pieces = [...scrollScene.querySelectorAll(".assembly-product")];
  const restingRotations = [-8, 7, -7, 12, -8, 8];
  let queued = false;

  function render() {
    queued = false;
    const rect = scrollScene.getBoundingClientRect();
    const travel = Math.max(1, rect.height - window.innerHeight);
    const progress = Math.min(1, Math.max(0, -rect.top / travel));
    const settled = Math.min(1, progress / 0.82);
    const distanceScale = Math.min(1, Math.max(0.42, window.innerWidth / 1100));

    pieces.forEach((piece, index) => {
      const departure = 1 - settled;
      const x = Number(piece.dataset.fromX) * departure * distanceScale;
      const y = Number(piece.dataset.fromY) * departure * distanceScale;
      const angle = restingRotations[index] + Number(piece.dataset.fromRotation) * departure;
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
  requestRender();
}

const demoProductImage = document.getElementById("demo-product-image");
if (demoProductImage) {
  const catalog = {
    "brown-script": ["LFDY Jacquard Beanie", "LFDY", "LFDY", "https://livefastdieyoung.com/en-us/products/lfdy-jacquard-beanie-13"],
    "green-stripe": ["Striped beanie", "Top Headwear", "Amazon", "https://www.amazon.com/dp/B076147M54"],
    "rust-vintage": ["Reclaimed Vintage beanie", "Reclaimed Vintage", "ASOS", "https://www.asos.com/de/reclaimed-vintage/reclaimed-vintage-unisex-skull-cap-strickmutze-in-rostrot-mit-logo/prd/208475824"],
    "blue-logo": ["Stüssy skullcap", "Stüssy", "AFewVibe", "https://afewvibe.com/products/stussy-brushed-out-stock-skullcap-blue"],
    "burgundy-bird": ["Arc’teryx Grotto Toque", "Arc’teryx", "Arc’teryx", "https://arcteryx.com/us/en/shop/grotto-toque-0980?colour=17704"],
    "coral-wave": ["Blue Tomato Y2K Beanie", "Blue Tomato", "MyBestBrands", "https://www.mybestbrands.de/marken/blue-tomato/accessoires/252.a0a5532f1c90c75168bdd99e9aca1a0e"],
    "black-columbia": ["Columbia Heat II Beanie", "Columbia", "Columbia", "https://www.columbia.com/p/columbia-heat-ii-beanie-2053191.html"],
    "slate-bird": ["Arc’teryx Bird Head Toque", "Arc’teryx", "StockX", "https://stockx.com/arcteryx-bird-head-toque-nightscape-glacial"],
    "lilac-mountain": ["Blue Bison Mountain Peaks Beanie", "Blue Bison", "Blue Bison", "https://www.bluebisonapparel.com/products/mountain-peaks-skull-cap-beanie-purple"],
    "bird-head-yellow": ["Arc’teryx Bird Head Toque", "Arc’teryx", "Arc’teryx", "https://arcteryx.com/us/en/shop/bird-head-toque"],
    "blue-flame": ["Blue Flame Skull Cap Beanie", "Blue Bison", "Blue Bison", "https://www.bluebisonapparel.com/products/blue-flame-skull-cap-beanie"],
    "orange-peaks": ["Mountain Peaks Skull Cap Beanie", "Blue Bison", "Blue Bison", "https://www.bluebisonapparel.com/products/mountain-peaks-skull-cap-beanie-orange"],
  };
  const slug = window.location.pathname.split("/").filter(Boolean).at(-1);
  const product = catalog[slug];
  if (product) {
    const [name, brand, merchant, productURL] = product;
    demoProductImage.src = `/assets/beanie-${slug}.webp`;
    demoProductImage.alt = name;
    document.getElementById("demo-product-title").textContent = name;
    document.getElementById("demo-product-brand").textContent = brand;
    const productLink = document.getElementById("demo-product-link");
    productLink.href = productURL;
    productLink.querySelector("span").textContent = `Buy from ${merchant}`;
    document.title = `${name} · Stacks`;
  }
}

const demoShareButton = document.querySelector(".demo-share-action");
if (demoShareButton) {
  demoShareButton.addEventListener("click", async () => {
    const url = new URL("/demo/beanies", window.location.origin).href;
    try {
      if (navigator.share) {
        await navigator.share({ title: "Beanies by Alvin Yakatori · Stacks", url });
      } else {
        await navigator.clipboard.writeText(url);
        document.getElementById("demo-share-status").textContent = "Beanies link copied";
      }
    } catch (error) {
      if (error.name !== "AbortError") document.getElementById("demo-share-status").textContent = "Could not share this Stack";
    }
  });
}
