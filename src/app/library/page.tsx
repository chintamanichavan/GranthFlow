import { getServerSession } from 'next-auth'
import { redirect } from 'next/navigation'
import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient()

export default async function Library() {
  const session = await getServerSession()

  if (!session?.user) {
    redirect('/auth/signin')
  }

  const books = await prisma.book.findMany({
    where: {
      users: {
        some: {
          email: session.user.email!,
        },
      },
    },
    include: {
      readingProgress: {
        where: {
          userId: session.user.id,
        },
        select: {
          page: true,
        },
      },
    },
  })

  return (
    <main className="container mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-8 text-secondary-900 dark:text-white">
        My Library
      </h1>

      {books.length === 0 ? (
        <div className="text-center py-12">
          <h2 className="text-xl text-secondary-600 dark:text-secondary-400 mb-4">
            Your library is empty
          </h2>
          <p className="text-secondary-500 dark:text-secondary-500 mb-8">
            Start exploring books to add them to your library
          </p>
          <a
            href="/explore"
            className="btn-primary inline-block"
          >
            Explore Books
          </a>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
          {books.map((book) => (
            <div
              key={book.id}
              className="card hover:shadow-lg transition-shadow cursor-pointer"
            >
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
              {book.readingProgress[0] && (
                <div className="text-sm text-secondary-500 dark:text-secondary-500">
                  Progress: {book.readingProgress[0].page} pages
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </main>
  )
} 