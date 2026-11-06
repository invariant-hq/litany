import { fileURLToPath } from "node:url";
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import links from "starlight-links-validator";
import hypha from "starlight-theme-hypha";

// litany's documentation site, published to GitHub Pages by
// .github/workflows/docs.yml. `make docs` builds it into _build/docs: odoc's
// reference from the .mli files into public/reference/ first, then the rule
// catalog into src/content/docs/reference/rules/, written by catalog.ts from
// `litany rules` and `litany explain`, so it cannot drift from the code.
//
// A page imports a whole file of examples/ or lib/ with `?raw` into Starlight's
// <Code>, so what it shows of them is built with the repository; short snippets
// and console samples stay inline, and nothing compiles those. A missing
// file, or a link to a page or a heading that is not there, fails the build.
const repository = fileURLToPath(new URL("..", import.meta.url));

export default defineConfig({
  site: "https://hyphatech.github.io",
  base: "/litany",
  outDir: `${repository}_build/docs`,
  vite: {
    resolve: {
      // A page imports an example as "@examples/<path>?raw", and a rule of
      // the catalog as "@lib/rules/<file>?raw".
      alias: { "@examples": `${repository}examples`, "@lib": `${repository}lib` },
    },
  },
  integrations: [
    starlight({
      title: "litany",
      description: "A linter for OCaml that reads what the compiler wrote.",
      logo: { dark: "starlight-theme-hypha/assets/hypha.webp", light: "starlight-theme-hypha/assets/hypha-day.webp" },
      favicon: "/favicon-32.png",
      head: [
        { tag: "link", attrs: { rel: "icon", type: "image/png", sizes: "16x16", href: "/litany/favicon-16.png" } },
        { tag: "link", attrs: { rel: "apple-touch-icon", sizes: "180x180", href: "/litany/apple-touch-icon.png" } },
      ],
      plugins: [
        hypha({
          brand: "hypha",
          github: "hyphatech/litany",
          tabs: { "Start here": "rocket", Guides: "book-open", Reference: "library" },
          links: [{ label: "Hypha Stack", href: "https://hyphatech.io/stack", icon: "layers" }],
        }),
        // The reference is odoc's, in public/, which the validator cannot see.
        links({ exclude: ["**/reference/litany/**"] }),
      ],
      sidebar: [
        { label: "Start here", items: ["index"] },
        {
          label: "Guides",
          items: [
            "guide/selecting-rules",
            "guide/configuration",
            "guide/suppression",
            "guide/fixing",
            "guide/build-integration",
            "guide/ci",
            "guide/writing-a-rule",
            "guide/custom-binary",
          ],
        },
        {
          label: "Reference",
          items: ["reference", { autogenerate: { directory: "reference/rules" } }],
        },
      ],
    }),
  ],
});
