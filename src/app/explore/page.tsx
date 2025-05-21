import { getServerSession } from 'next-auth'
import { PrismaClient } from '@prisma/client'
import { redirect } from 'next/navigation'
import { addBookToLibrary } from '../actions'
import { BookCard } from './BookCard'

const prisma = new PrismaClient()

export default async function Explore() {
  const session = await getServerSession()

  if (!session?.user) {
    redirect('/auth/signin')
  }

  const books = await prisma.book.findMany({
    take: 20,
    orderBy: {
      createdAt: 'desc',
    },
  })

  return (
    <main className="container mx-auto px-4 py-8">
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-3xl font-bold text-secondary-900 dark:text-white">
          Explore Books
        </h1>
        <div className="relative">
          <input
            type="search"
            placeholder="Search books..."
            className="input pl-10"
          />
          <svg
            className="w-5 h-5 text-secondary-400 absolute left-3 top-1/2 transform -translate-y-1/2"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
        {books.map((book) => (
          <BookCard key={book.id} book={book} />
        ))}
      </div>
    </main>
  )
} 