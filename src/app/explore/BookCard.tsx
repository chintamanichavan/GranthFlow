'use client'

import { Book } from '@prisma/client'
import { addBookToLibrary } from '../actions'

interface BookCardProps {
  book: Book
}

export function BookCard({ book }: BookCardProps) {
  return (
    <div className="card hover:shadow-lg transition-shadow">
      {book.coverImage ? (
        <img
          src={book.coverImage}
          alt={book.title}
          className="w-full h-48 object-cover rounded-lg mb-4"
        />
      ) : (
        <div className="w-full h-48 bg-secondary-200 dark:bg-secondary-700 rounded-lg mb-4 flex items-center justify-center">
          <span className="text-4xl">📚</span>
        </div>
      )}
      <h3 className="font-semibold text-lg mb-2 text-secondary-900 dark:text-white">
        {book.title}
      </h3>
      <p className="text-secondary-600 dark:text-secondary-400 mb-2">
        {book.author}
      </p>
      <p className="text-sm text-secondary-500 dark:text-secondary-500 mb-4 line-clamp-2">
        {book.description}
      </p>
      <form action={async () => {
        'use server'
        await addBookToLibrary(book.id)
      }}>
        <button
          type="submit"
          className="btn-primary w-full"
        >
          Add to Library
        </button>
      </form>
    </div>
  )
} 