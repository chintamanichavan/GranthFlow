# GranthFlow

GranthFlow is a modern web-based book reading platform inspired by Apple Books. It provides a seamless reading experience with features like library management, reading progress tracking, and a beautiful user interface.

## Features

- 📚 Browse and discover books
- 📖 Clean, distraction-free reading interface
- 📱 Responsive design for all devices
- 🔐 User authentication and personal library
- 📝 Bookmarking and notes
- 📊 Reading progress tracking
- 🌙 Dark mode support

## Tech Stack

- Next.js 14
- TypeScript
- Tailwind CSS
- Prisma (PostgreSQL)
- NextAuth.js
- React

## Getting Started

1. Clone the repository
2. Install dependencies:
   ```bash
   npm install
   ```
3. Set up your environment variables:
   ```bash
   cp .env.example .env.local
   ```
4. Set up the database:
   ```bash
   npx prisma db push
   ```
5. Run the development server:
   ```bash
   npm run dev
   ```

Visit [http://localhost:3000](http://localhost:3000) to see the application.

## Development

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run start` - Start production server
- `npm run lint` - Run ESLint

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 