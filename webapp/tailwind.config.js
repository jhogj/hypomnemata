/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // Paleta "cool" do wireframe — mineral frio
        paper: {
          bg: "#f0eff0",
          sidebar: "#e8e7e8",
          card: "#fafafa",
          ink: "#1a1a1f",
          mid: "#6a6a7a",
          light: "#aaaabc",
          accent: "#4a4a6a",
          border: "#c0bfd0",
          tag: "#e4e3f0",
        },
      },
      fontFamily: {
        sans: ["'Space Grotesk'", "system-ui", "sans-serif"],
      },
    },
  },
  plugins: [],
};
