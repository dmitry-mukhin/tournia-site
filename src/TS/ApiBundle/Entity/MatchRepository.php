<?php

namespace TS\ApiBundle\Entity;

use Doctrine\ORM\EntityRepository;

/**
 * MatchRepository
 *
 * This class was generated by the Doctrine ORM. Add your own custom
 * repository methods below.
 */
class MatchRepository extends EntityRepository
{
	/**
	 * Get the last localId of a tournament
	 *
	 * @return int
	 */
	public function getLastLocalId($tournament) {
		$em = $this->getEntityManager();
		
		$query = $this->createQueryBuilder('m')
			->where('m.tournament = :tournament')
			->setParameter('tournament', $tournament)
			->orderBy('m.localId', 'DESC')
			->setMaxResults(1)
			->getQuery();
		
		try {
			$match = $query->getSingleResult();
			return intval($match->getLocalId());
		} catch (\Doctrine\Orm\NoResultException $e) {
			return 0;	
		}
	}
	
	/**
	 * Get all rounds of a pool
	 * @param \TS\ApiBundle\Entity\Tournament $tournament
	 * @param \TS\ApiBundle\Entity\Pool $pool The pool to search for, can be null, for when to search to all rounds in the entire tournament
	 * @return array, with as a key the round number. Result is sorted by key number (so the last round last)
	 */
	public function getAllRounds($tournament, $pool=null) {
		$em = $this->getEntityManager();
		
		$query = $this->createQueryBuilder('m')
			->where('m.tournament = :tournament')
			->setParameter('tournament', $tournament);
		if (!is_null($pool)) {
			$query = $query
				->andWhere('m.pool = :pool')
				->setParameter('pool', $pool);
		}
		$query = $query
			->groupBy('m.round')
			->getQuery();
		
		$res = array();
		$matches = $query->getResult();
		foreach ($matches as $match) {
			$round = $match->getRound();
			$roundNr = substr($round, strrpos($round, " "));
			$roundNr = intval($roundNr);
			$res[$roundNr] = $round;
		}
		ksort($res);
		return $res;
	}

	/**
	 * Remove a match and underlying announcements (but doesn't flush)
	 * @param \TS\ApiBundle\Entity\Match $match
	 */
	public function remove($match) {
		foreach ($match->getAnnouncements() as $announcement) {
			$this->getEntityManager()->remove($announcement);
		}
		$this->getEntityManager()->remove($match);
	}
}
